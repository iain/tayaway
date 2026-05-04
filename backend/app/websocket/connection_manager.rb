# frozen_string_literal: true

require "json"

module Websocket
  # Singleton that tracks WebSocket connections and their workspace associations.
  #
  # All access happens from fibers running on the same Falcon reactor — request
  # handlers register/unregister, the Listener task broadcasts, the Keepalive
  # task pings — so no OS-level locking is needed. Methods that perform I/O
  # (writing to a websocket yields to the reactor) take a snapshot of the
  # connection set first so concurrent register/unregister doesn't surprise
  # the iteration.
  #
  # @example
  #   conn_id = ConnectionManager.instance.register(connection, user_id)
  #   ConnectionManager.instance.set_workspaces(conn_id, ["workspace-uuid"])
  #   ConnectionManager.instance.broadcast_to_workspace("workspace-uuid", { type: "update", data: {...} })
  #   ConnectionManager.instance.unregister(conn_id)
  class ConnectionManager
    include Singleton

    def initialize
      @connections = {}
      @workspace_connections = {}
    end

    def register(websocket, user_id, session_id = nil)
      connection_id = SecureRandom.uuid
      uid = user_id.to_s
      @connections[connection_id] = Connection.new(
        id: connection_id,
        websocket: websocket,
        user_id: uid,
        session_id: session_id
      )
      APP_LOGGER.info { "[ConnectionManager] User #{uid} connected (conn: #{connection_id}, total: #{@connections.size})" }
      connection_id
    end

    def unregister(connection_id)
      connection = @connections.delete(connection_id)
      return unless connection

      # Clean up workspace associations
      connection.workspace_ids.each do |workspace_id|
        ws_conns = @workspace_connections[workspace_id]
        next unless ws_conns

        ws_conns.delete(connection_id)
        @workspace_connections.delete(workspace_id) if ws_conns.empty?
      end
      APP_LOGGER.info { "[ConnectionManager] User #{connection.user_id} disconnected (conn: #{connection_id}, total: #{@connections.size})" }
    end

    def set_workspaces(connection_id, workspace_ids)
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
        @workspace_connections[ws_id].add(connection_id)
      end
      APP_LOGGER.info { "[ConnectionManager] User #{connection.user_id} switched workspaces (conn: #{connection_id}, workspaces: #{workspace_ids.join(', ')})" }
    end

    def set_membership(connection_id, membership)
      connection = @connections[connection_id]
      connection&.membership = membership
    end

    def update_last_pong(connection_id)
      connection = @connections[connection_id]
      connection&.last_pong_at = Time.now
    end

    # Ping all connections and unregister those that have not responded within
    # the idle timeout. Returns the number of connections pruned.
    def ping_all(idle_timeout:)
      deadline = Time.now - idle_timeout
      stale_ids = []

      # Snapshot so register/unregister from concurrent fibers (or recursion
      # via unregister) cannot mutate the hash mid-iteration.
      @connections.dup.each do |connection_id, connection|
        if connection.last_pong_at < deadline
          stale_ids << connection_id
        else
          begin
            connection.websocket.write({ type: "ping" }.to_json)
            connection.websocket.flush
          rescue StandardError => e
            APP_LOGGER.error { "[ConnectionManager] Error pinging conn #{connection_id}: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}" }
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

    def broadcast_to_workspace(workspace_id, message, policy_context: nil)
      connection_ids = (@workspace_connections[workspace_id] || Set.new).to_a

      if policy_context
        connection_ids.each do |connection_id|
          connection = @connections[connection_id]
          next unless connection

          personalized = attach_permissions(message, connection.membership, policy_context)
          send_to_connection(connection, connection_id, personalized.to_json, workspace_id)
        end
      else
        json_message = message.to_json
        connection_ids.each do |connection_id|
          connection = @connections[connection_id]
          next unless connection

          send_to_connection(connection, connection_id, json_message, workspace_id)
        end
      end
    end

    def connections_for_user(user_id)
      @connections.values.select { |c| c.user_id == user_id }.map(&:id)
    end

    # Send a session_revoked message and close all connections tied to the given session IDs.
    def close_sessions(session_ids)
      return if session_ids.empty?

      id_set = session_ids.to_set
      targets = @connections.values.select { |c| c.session_id && id_set.include?(c.session_id) }

      message = { type: "session_revoked" }.to_json
      targets.each do |connection|
        begin
          connection.websocket.write(message)
          connection.websocket.flush
        rescue StandardError => e
          APP_LOGGER.error { "[ConnectionManager] Error sending session_revoked to conn #{connection.id}: #{e.class}: #{e.message}" }
        end
        unregister(connection.id)
      end

      APP_LOGGER.info { "[ConnectionManager] Closed #{targets.size} connection(s) for revoked sessions" } if targets.any?
    end

    def connection_count
      @connections.size
    end

    private

    def attach_permissions(message, membership, policy_context)
      PermissionAttacher.attach_to_message(message, membership, policy_context)
    end

    def send_to_connection(connection, connection_id, json_message, workspace_id)
      connection.websocket.write(json_message)
      connection.websocket.flush
    rescue StandardError => e
      APP_LOGGER.error { "[ConnectionManager] Error broadcasting to workspace #{workspace_id}, conn #{connection_id}: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}" }
      unregister(connection_id)
    end

    # Internal connection struct
    class Connection
      attr_reader :id, :websocket, :user_id, :session_id
      attr_accessor :workspace_ids, :last_pong_at, :membership

      def initialize(
        id:,
        websocket:,
        user_id:,
        session_id:,
        workspace_ids: Set.new,
        last_pong_at: Time.now
      )
        @id = id
        @websocket = websocket
        @user_id = user_id
        @session_id = session_id
        @workspace_ids = workspace_ids
        @last_pong_at = last_pong_at
      end
    end
  end
end
