# frozen_string_literal: true

require "async"
require "async/semaphore"
require "json"

module Websocket
  # Background fiber that listens for PostgreSQL NOTIFY events, fetches the
  # full data, and dispatches to ConnectionManager for WebSocket broadcasting.
  #
  # Runs as an Async task on the worker's reactor — one listener fiber per
  # forked worker process. PG NOTIFY fans out to every backend listening on
  # the channel, so each worker subscribes independently and broadcasts only
  # to the WebSockets it owns. `DB.listen` borrows a connection from the
  # main pool, so lifecycle (and graceful cancellation) stays tied to the
  # Sequel pool instead of a side-channel `Sequel.connect`.
  #
  # Each notification is handled in a child fiber under a semaphore: the
  # listener returns to `wait_for_notify` as soon as the dispatch is
  # scheduled, so a slow `connection.write` to one client cannot stall
  # the next workspace's broadcast. The semaphore caps concurrency so a
  # NOTIFY storm doesn't exhaust the Sequel pool or accumulate fibers.
  module Listener
    CHANNEL = "tayaway_objects"
    # NOTIFYs that arrive between the connection failing and the
    # re-LISTEN are lost. Clients catch up via the next partial sync,
    # so the only cost of a longer delay is broadcast latency for
    # currently-connected clients — keep it short.
    RETRY_DELAY = 1
    # Sized below the web pool's free slots (database.rb pool minus the
    # listener's own held connection minus headroom for request fibers)
    # so a broadcast burst can't pool-timeout request handlers.
    BROADCAST_CONCURRENCY = 8

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
        object_type = data[:objectType]
        object_id = data[:objectId]
        action = data[:action]
        return unless object_type && object_id && action

        config = type_config(object_type)
        unless config
          APP_LOGGER.warn { "[Listener] Unknown object type: #{object_type}" }
          return
        end

        case action
        when "update"
          # Load the object once and ask the registry for its audience set.
          # If the object disappeared between notify and fetch, drop the
          # notification — the corresponding delete NOTIFY will handle it.
          object = find_object(config.key, object_id)
          return unless object
          audiences = config.serializer_class.broadcast_audiences_for(object)
          audiences.each do |audience|
            dispatch_update(connections, audience, config, object)
          end
        when "delete"
          # Deletes carry the audience inline because the object can no longer
          # be reloaded to derive it.
          audience = { kind: data[:audience], id: data[:audienceId] }
          return unless audience[:kind] && audience[:id]
          dispatch_delete(connections, audience, config, object_id)
        end
      rescue JSON::ParserError => e
        APP_LOGGER.error { "[Listener] Invalid JSON payload: #{e.message}" }
      rescue StandardError => e
        APP_LOGGER.error { "[Listener] Error handling notification: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}" }
      end

      private

      def dispatch_update(connections, audience, config, object)
        case audience[:kind]
        when "workspace"
          # Thread a PolicyContext so the connection manager can attach
          # per-recipient permissions; PoolSerializer needs the workspace
          # id to compute the right policy view.
          pool = PoolSerializer.new(workspace_id: audience[:id], collect_policy_contexts: true)
          pool.add(config.key, [object])
          message = {
            type: "broadcast",
            workspaceId: audience[:id],
            action: "update",
            data: { objects: pool.to_a }
          }
          policy_context = Websocket::PolicyContext.new(
            raw_objects: pool.raw_objects,
            policy_contexts: pool.policy_contexts
          )
          connections.broadcast_to_workspace(audience[:id], message, policy_context: policy_context)
        when "user"
          # No policy context — the user is the audience, so visibility
          # is decided at dispatch time, not by per-viewer permission diffs.
          pool = PoolSerializer.new
          pool.add(config.key, [object])
          message = {
            type: "broadcast",
            action: "update",
            data: { objects: pool.to_a }
          }
          connections.broadcast_to_user(audience[:id], message)
        else
          APP_LOGGER.warn { "[Listener] Unknown audience kind: #{audience[:kind].inspect}" }
        end
      end

      def dispatch_delete(connections, audience, config, object_id)
        deleted_data = { deleted: [{ objectType: config.client_type, id: object_id }] }
        case audience[:kind]
        when "workspace"
          message = {
            type: "broadcast",
            workspaceId: audience[:id],
            action: "delete",
            data: deleted_data
          }
          connections.broadcast_to_workspace(audience[:id], message)
        when "user"
          message = { type: "broadcast", action: "delete", data: deleted_data }
          connections.broadcast_to_user(audience[:id], message)
        else
          APP_LOGGER.warn { "[Listener] Unknown audience kind: #{audience[:kind].inspect}" }
        end
      end

      def semaphore
        @_semaphore ||= Async::Semaphore.new(BROADCAST_CONCURRENCY)
      end

      def listen_once(connections)
        APP_LOGGER.info { "[Listener] Listening on #{CHANNEL}" }
        DB.listen(CHANNEL, loop: true) do |_channel, _pid, payload|
          semaphore.async do
            handle_notification(payload, connections)
          end
        end
      end
    end
  end
end
