# typed: true
# frozen_string_literal: true

require "json"

module Websocket
  # Singleton that tracks WebSocket connections and their workspace associations.
  # Thread-safe through mutex-protected operations.
  #
  # @example
  #   conn_id = ConnectionManager.instance.register(connection, user_id)
  #   ConnectionManager.instance.set_workspaces(conn_id, ["workspace-uuid"])
  #   ConnectionManager.instance.broadcast_to_workspace("workspace-uuid", { type: "update", data: {...} })
  #   ConnectionManager.instance.unregister(conn_id)
  class ConnectionManager
    extend T::Sig
    include Singleton

    sig { void }
    def initialize
      @mutex = Mutex.new
      @connections = T.let({}, T::Hash[String, Connection])
      @workspace_connections = T.let({}, T::Hash[String, T::Set[String]])
    end

    sig { params(websocket: T.untyped, user_id: T.any(String, UUID)).returns(String) }
    def register(websocket, user_id)
      connection_id = SecureRandom.uuid
      @mutex.synchronize do
        @connections[connection_id] = Connection.new(
          id: connection_id,
          websocket: websocket,
          user_id: user_id.to_s
        )
      end
      connection_id
    end

    sig { params(connection_id: String).void }
    def unregister(connection_id)
      @mutex.synchronize do
        connection = @connections.delete(connection_id)
        return unless connection

        # Clean up workspace associations
        connection.workspace_ids.each do |workspace_id|
          ws_conns = @workspace_connections[workspace_id]
          next unless ws_conns

          ws_conns.delete(connection_id)
          @workspace_connections.delete(workspace_id) if ws_conns.empty?
        end
      end
    end

    sig { params(connection_id: String, workspace_ids: T::Array[String]).void }
    def set_workspaces(connection_id, workspace_ids)
      @mutex.synchronize do
        connection = @connections[connection_id]
        return unless connection

        # Clear old workspace associations
        connection.workspace_ids.each do |old_ws_id|
          ws_conns = @workspace_connections[old_ws_id]
          next unless ws_conns

          ws_conns.delete(connection_id)
          @workspace_connections.delete(old_ws_id) if ws_conns.empty?
        end

        # Set new workspace associations
        connection.workspace_ids = workspace_ids.to_set
        workspace_ids.each do |ws_id|
          @workspace_connections[ws_id] ||= Set.new
          T.must(@workspace_connections[ws_id]).add(connection_id)
        end
      end
    end

    sig { params(connection_id: String).void }
    def update_last_pong(connection_id)
      @mutex.synchronize do
        connection = @connections[connection_id]
        connection&.last_pong_at = Time.now
      end
    end

    # Ping all connections and unregister those that have not responded within
    # the idle timeout. Returns the number of connections pruned.
    sig { params(idle_timeout: Numeric).returns(Integer) }
    def ping_all(idle_timeout:)
      deadline = Time.now - idle_timeout
      stale_ids = []

      connection_snapshot = @mutex.synchronize { @connections.dup }

      connection_snapshot.each do |connection_id, connection|
        if connection.last_pong_at < deadline
          stale_ids << connection_id
        else
          begin
            connection.websocket.write({ type: "ping" }.to_json)
            connection.websocket.flush
          rescue StandardError => e
            APP_LOGGER.error { "[ConnectionManager] Error pinging conn #{connection_id}: #{e.message}" }
            stale_ids << connection_id
          end
        end
      end

      stale_ids.each do |connection_id|
        APP_LOGGER.info { "[ConnectionManager] Pruning stale connection #{connection_id}" }
        unregister(connection_id)
      end

      stale_ids.size
    end

    sig { params(workspace_id: String, message: T::Hash[Symbol, T.untyped]).void }
    def broadcast_to_workspace(workspace_id, message)
      connection_ids = @mutex.synchronize { (@workspace_connections[workspace_id] || Set.new).to_a }
      json_message = message.to_json

      connection_ids.each do |connection_id|
        connection = @mutex.synchronize { @connections[connection_id] }
        next unless connection

        begin
          connection.websocket.write(json_message)
          connection.websocket.flush
        rescue StandardError => e
          APP_LOGGER.error { "[ConnectionManager] Error broadcasting to workspace #{workspace_id}, conn #{connection_id}: #{e.message}" }
          unregister(connection_id)
        end
      end
    end

    sig { params(user_id: String).returns(T::Array[String]) }
    def connections_for_user(user_id)
      @mutex.synchronize do
        @connections.values.select { |c| c.user_id == user_id }.map(&:id)
      end
    end

    sig { returns(Integer) }
    def connection_count
      @mutex.synchronize { @connections.size }
    end

    # Internal connection struct
    class Connection < T::Struct
      const :id, String
      const :websocket, Object
      const :user_id, String
      prop :workspace_ids, T::Set[String], factory: -> { Set.new }
      prop :last_pong_at, Time, factory: -> { Time.now }
    end
  end
end
