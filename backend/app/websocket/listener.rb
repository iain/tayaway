# frozen_string_literal: true

require "json"
require "concurrent"

module Websocket
  # Background task that listens for PostgreSQL NOTIFY events, fetches the
  # full data, and dispatches to ConnectionManager for WebSocket broadcasting.
  #
  # Uses a dedicated DB connection to avoid blocking the connection pool.
  #
  # @example
  #   Listener.start  # Starts background thread
  #   Listener.stop   # Stops the listener
  class Listener
    CHANNEL = "tayaway_objects"
    RETRY_DELAY = 5 # seconds

    class << self
      def start
        return if running_flag.true?

        running_flag.make_true
        @listen_db = nil
        @thread = Thread.new { run_loop }
        @thread.abort_on_exception = true
        APP_LOGGER.info { "[Listener] Started PostgreSQL LISTEN on #{CHANNEL}" }
      end

      def stop
        return unless running_flag.true?

        running_flag.make_false
        # Disconnect the listen connection to unblock the listen loop
        @listen_db&.disconnect
        @thread&.join(RETRY_DELAY + 1)
        @thread = nil
        APP_LOGGER.info { "[Listener] Stopped" }
      end

      def running?
        running_flag.true?
      end

      def type_config(object_type)
        ObjectRegistry::BY_KEY[object_type]
      end

      def find_object(object_type, object_id)
        config = type_config(object_type)
        return nil unless config

        model_class = Object.const_get(config.model)
        model_class.find(object_id)
      end

      private

      def running_flag
        @_running_flag ||= Concurrent::AtomicBoolean.new(false)
      end

      def run_loop
        while running_flag.true?
          listen_with_retry
        end
      end

      def listen_with_retry
        # Create a dedicated connection for listening (stored for graceful shutdown)
        @listen_db = Sequel.connect(ENV.fetch("DATABASE_URL"))
        @listen_db.listen(CHANNEL, loop: true) do |_channel, _pid, payload|
          break unless running_flag.true?

          handle_notification(payload)
        end
      rescue StandardError => e
        if running_flag.true?
          APP_LOGGER.error { "[Listener] Error in listen loop: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}" }
          APP_LOGGER.info { "[Listener] Retrying in #{RETRY_DELAY} seconds..." }
          sleep RETRY_DELAY if running_flag.true?
        end
      ensure
        @listen_db&.disconnect
        @listen_db = nil
      end

      def handle_notification(payload)
        data = JSON.parse(payload, symbolize_names: true)
        workspace_id = data[:workspaceId]
        object_type = data[:objectType]
        object_id = data[:objectId]
        action = data[:action]
        return unless workspace_id && object_type && object_id && action

        config = type_config(object_type)
        unless config
          APP_LOGGER.warn { "[Listener] Unknown object type: #{object_type}" }
          return
        end

        message = { type: "broadcast", workspaceId: workspace_id, action: action }
        policy_context = nil

        case action
        when "update"
          object = find_object(object_type, object_id)
          if object
            pool = PoolSerializer.new(workspace_id: workspace_id)
            pool.add(config.key, [object])
            message[:data] = { objects: pool.to_a }
            policy_context = Websocket::PolicyContext.new(
              raw_objects: { config.key => object },
              kwargs: config.serializer_class.policy_context(object)
            )
          else
            # Object was deleted between notify and fetch
            message[:action] = "delete"
            message[:data] = { deleted: [{ objectType: config.client_type, id: object_id }] }
          end
        when "delete"
          message[:data] = { deleted: [{ objectType: config.client_type, id: object_id }] }
        end

        Websocket::ConnectionManager.instance.broadcast_to_workspace(
          workspace_id, message, policy_context: policy_context
        )
      rescue JSON::ParserError => e
        APP_LOGGER.error { "[Listener] Invalid JSON payload: #{e.message}" }
      rescue StandardError => e
        APP_LOGGER.error { "[Listener] Error handling notification: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}" }
      end
    end
  end
end
