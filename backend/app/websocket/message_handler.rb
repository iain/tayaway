# frozen_string_literal: true

require "json"

module Websocket
  # Handles incoming WebSocket messages. Extracted from the App class to avoid
  # defining private methods on App from route files (which risks name collisions).
  module MessageHandler
    class << self
      def safe_parse_time(value)
        return nil unless value

        Time.parse(value)
      rescue ArgumentError
        nil
      end

      def handle(connection, connection_id, user_id, raw_message)
        data = JSON.parse(raw_message, symbolize_names: true)
        type = data[:type]

        case type
        when "ping"
          # The browser-side keepalive only sends `ping` and reads the
          # `pong` reply; it never sends a `pong` of its own. So the
          # inbound ping is the liveness signal we use to keep this
          # connection out of the keepalive sweep — without bumping
          # last_pong_at here the server prunes every connection roughly
          # 90 s after it opens, which silently breaks broadcast routing
          # while the WebSocket itself stays open.
          Websocket::ConnectionManager.instance.update_last_pong(connection_id)
          connection.write({ type: "pong", gitSha: APP_CONFIG.git_sha }.to_json)
        when "switch_workspace"
          switch_workspace(connection, user_id, data[:workspaceId], data[:since])
        else
          connection.write({ type: "error", message: "Unknown message type" }.to_json)
        end
      rescue JSON::ParserError
        connection.write({ type: "error", message: "Invalid JSON" }.to_json)
      rescue StandardError => e
        APP_LOGGER.error { "[WebSocket] MessageHandler error: #{e.message}" }
        connection.write({ type: "error", message: "Internal error" }.to_json)
      end

      private

      # The connection is already subscribed to every workspace the user
      # belongs to (subscribed at auth), so switching is purely "send me a
      # fresh sync for this workspace". No subscription change, no
      # membership update — both were established at auth time.
      def switch_workspace(connection, user_id, workspace_id, since = nil)
        unless workspace_id
          connection.write({ type: "error", message: "Missing workspaceId" }.to_json)
          return
        end

        membership = WorkspaceMembership.find_by_workspace_and_user(workspace_id, user_id)
        unless membership
          connection.write({ type: "error", message: "Not a member of this workspace" }.to_json)
          return
        end

        since_time = safe_parse_time(since)
        result = Sync::WorkspaceSync.call(workspace_id: workspace_id, since: since_time, membership: membership)
        connection.write({ type: "sync", data: result }.to_json)
      end
    end
  end
end
