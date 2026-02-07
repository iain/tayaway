# typed: true
# frozen_string_literal: true

require "json"

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
    extend T::Sig

    CHANNEL = "tayaway_objects"
    RETRY_DELAY = 5 # seconds

    # Registry mapping object types to their model class and pool serializer method
    OBJECT_TYPES = T.let(
      {
        "event" => { model: "Event", pool_method: :add_event },
        "user" => { model: "User", pool_method: :add_user },
        "date_range" => { model: "DateRange", pool_method: :add_date_range },
        "vote" => { model: "Vote", pool_method: :add_vote }
      }.freeze,
      T::Hash[String, T::Hash[Symbol, T.untyped]]
    )

    class << self
      extend T::Sig

      sig { void }
      def start
        return if @running

        @running = true
        @thread = Thread.new { run_loop }
        @thread.abort_on_exception = true
        puts "[Listener] Started PostgreSQL LISTEN on #{CHANNEL}"
      end

      sig { void }
      def stop
        return unless @running

        @running = false
        @thread&.kill
        @thread = nil
        puts "[Listener] Stopped"
      end

      sig { returns(T::Boolean) }
      def running?
        !!@running
      end

      sig { params(object_type: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def type_config(object_type)
        OBJECT_TYPES[object_type]
      end

      sig { params(object_type: String, object_id: String).returns(T.untyped) }
      def find_object(object_type, object_id)
        config = type_config(object_type)
        return nil unless config

        model_class = Object.const_get(config[:model])
        model_class.find(object_id)
      end

      private

      sig { void }
      def run_loop
        while @running
          listen_with_retry
        end
      end

      sig { void }
      def listen_with_retry
        # Create a dedicated connection for listening
        db = Sequel.connect(ENV.fetch("DATABASE_URL"))

        begin
          db.listen(CHANNEL, loop: true) do |_channel, _pid, payload|
            break unless @running

            handle_notification(payload)
          end
        rescue StandardError => e
          warn "[Listener] Error in listen loop: #{e.message}"
          warn "[Listener] Retrying in #{RETRY_DELAY} seconds..."
          sleep RETRY_DELAY if @running
        ensure
          db.disconnect
        end
      end

      sig { params(payload: String).void }
      def handle_notification(payload)
        data = JSON.parse(payload, symbolize_names: true)
        channel = data[:channel]
        object_type = data[:objectType]
        object_id = data[:objectId]
        action = data[:action]
        return unless channel && object_type && object_id && action

        config = type_config(object_type)
        unless config
          warn "[Listener] Unknown object type: #{object_type}"
          return
        end

        message = { type: "broadcast", channel: channel, action: action }

        case action
        when "update"
          object = find_object(object_type, object_id)
          if object
            pool = PoolSerializer.new
            pool.send(config[:pool_method], object)
            message[:data] = { objects: pool.to_a }
          else
            # Object was deleted between notify and fetch
            message[:action] = "delete"
            message[:data] = { deleted: [{ objectType: object_type, id: object_id }] }
          end
        when "delete"
          message[:data] = { deleted: [{ objectType: object_type, id: object_id }] }
        end

        Websocket::ConnectionManager.instance.broadcast(channel, message)
      rescue JSON::ParserError => e
        warn "[Listener] Invalid JSON payload: #{e.message}"
      rescue StandardError => e
        warn "[Listener] Error handling notification: #{e.message}"
      end
    end
  end
end
