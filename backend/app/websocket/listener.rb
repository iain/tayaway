# frozen_string_literal: true

require "async"
require "json"

module Websocket
  # Background task that listens for PostgreSQL NOTIFY events, fetches the
  # full data, and dispatches to ConnectionManager for WebSocket broadcasting.
  #
  # Runs as an Async task on the same reactor as request handlers, so it
  # cooperates with the rest of the worker via the fiber scheduler instead
  # of a separate OS thread. A dedicated DB connection avoids tying up the
  # main connection pool while LISTEN is parked waiting for notifies.
  #
  # @example
  #   Listener.start  # must be called from inside an Async reactor
  #   Listener.stop
  class Listener
    CHANNEL = "tayaway_objects"
    RETRY_DELAY = 5 # seconds

    class << self
      def start
        return if @task

        parent = Async::Task.current?
        raise "Websocket::Listener.start must be called inside an Async reactor" unless parent

        # Spawning on the reactor (not on the parent task) makes the lifetime
        # explicit: this task lives for the worker, not for whichever fiber
        # happened to call start.
        @task = parent.reactor.async do |task|
          task.annotate("Websocket::Listener")
          run_loop(task)
        end
        APP_LOGGER.info { "[Listener] Started PostgreSQL LISTEN on #{CHANNEL}" }
      end

      def stop
        return unless @task

        # Stopping the task raises Async::Stop in its fiber, which unwinds
        # through the parked db.listen call and runs the ensure block that
        # disconnects the dedicated PG connection.
        @task.stop
        @task = nil
        APP_LOGGER.info { "[Listener] Stopped" }
      end

      def running?
        !@task.nil? && !@task.finished?
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

      def run_loop(task)
        listen_with_retry(task) until task.stopped?
      end

      def listen_with_retry(task)
        db = Sequel.connect(ENV.fetch("DATABASE_URL"))
        db.listen(CHANNEL, loop: true) do |_channel, _pid, payload|
          handle_notification(payload)
        end
      rescue StandardError => e
        return if task.stopped?

        APP_LOGGER.error { "[Listener] Error in listen loop: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}" }
        APP_LOGGER.info { "[Listener] Retrying in #{RETRY_DELAY} seconds..." }
        task.sleep(RETRY_DELAY)
      ensure
        db&.disconnect
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
            pool = PoolSerializer.new(workspace_id: workspace_id, collect_policy_contexts: true)
            pool.add(config.key, [object])
            message[:data] = { objects: pool.to_a }
            # Pull raw_objects and per-object policy contexts from the pool so
            # fan-out children (task_items under a task_list, chores under a
            # chore_roster, participants under an expense) get permissions
            # computed on the broadcast side instead of silently shipping
            # without a permissions key.
            policy_context = Websocket::PolicyContext.new(
              raw_objects: pool.raw_objects,
              policy_contexts: pool.policy_contexts
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
