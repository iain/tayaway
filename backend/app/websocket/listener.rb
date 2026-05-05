# frozen_string_literal: true

require "async"
require "json"

module Websocket
  # Background fiber that listens for PostgreSQL NOTIFY events, fetches the
  # full data, and dispatches to ConnectionManager for WebSocket broadcasting.
  #
  # Runs as an Async task on the worker's reactor — one listener fiber per
  # forked worker process. PG NOTIFY fans out to every backend listening on
  # the channel, so each worker subscribes independently and broadcasts only
  # to the WebSockets it owns. The connection it parks on comes from the
  # main pool via DB.synchronize, which keeps lifecycle (and graceful
  # cancellation) tied to the Sequel pool instead of a side-channel
  # Sequel.connect.
  module Listener
    CHANNEL = "tayaway_objects"
    RETRY_DELAY = 5

    class << self
      def run(connections: ConnectionManager.instance)
        loop do
          listen_once(connections)
        rescue StandardError => e
          APP_LOGGER.error { "[Listener] Error: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}" }
          APP_LOGGER.info { "[Listener] Retrying in #{RETRY_DELAY}s" }
          Async::Task.current.sleep(RETRY_DELAY)
        end
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

      def handle_notification(payload, connections = ConnectionManager.instance)
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

        connections.broadcast_to_workspace(workspace_id, message, policy_context: policy_context)
      rescue JSON::ParserError => e
        APP_LOGGER.error { "[Listener] Invalid JSON payload: #{e.message}" }
      rescue StandardError => e
        APP_LOGGER.error { "[Listener] Error handling notification: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}" }
      end

      private

      def listen_once(connections)
        DB.synchronize do |raw|
          raw.query("LISTEN #{CHANNEL}")
          APP_LOGGER.info { "[Listener] Listening on #{CHANNEL}" }
          begin
            loop do
              raw.wait_for_notify do |_channel, _pid, payload|
                handle_notification(payload, connections)
              end
            end
          ensure
            raw.query("UNLISTEN *")
          end
        end
      end
    end
  end
end
