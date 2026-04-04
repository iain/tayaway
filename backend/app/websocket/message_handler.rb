# typed: true
# frozen_string_literal: true

require "json"

module Websocket
  # Handles incoming WebSocket messages. Extracted from the App class to avoid
  # defining private methods on App from route files (which risks name collisions).
  module MessageHandler
    class << self
      extend T::Sig

      sig { params(value: T.nilable(String)).returns(T.nilable(Time)) }
      def safe_parse_time(value)
        return nil unless value

        Time.parse(value)
      rescue ArgumentError
        nil
      end

      sig do
        params(
          connection: T.untyped,
          connection_id: String,
          user_id: T.untyped,
          raw_message: String
        ).void
      end
      def handle(connection, connection_id, user_id, raw_message)
        data = JSON.parse(raw_message, symbolize_names: true)
        type = data[:type]

        case type
        when "ping"
          connection.write({ type: "pong", gitSha: GIT_SHA }.to_json)
        when "pong"
          Websocket::ConnectionManager.instance.update_last_pong(connection_id)
        when "switch_workspace"
          switch_workspace(connection, connection_id, user_id, data[:workspaceId], data[:since])
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

      sig do
        params(
          connection: T.untyped,
          connection_id: String,
          user_id: T.untyped,
          workspace_id: T.nilable(String),
          since: T.nilable(String)
        ).void
      end
      def switch_workspace(connection, connection_id, user_id, workspace_id, since = nil)
        unless workspace_id
          connection.write({ type: "error", message: "Missing workspaceId" }.to_json)
          return
        end

        # Validate user is a member of this workspace
        membership = WorkspaceMembership.find_by_workspace_and_user(workspace_id, user_id)
        unless membership
          connection.write({ type: "error", message: "Not a member of this workspace" }.to_json)
          return
        end

        # Subscribe only to this workspace
        Websocket::ConnectionManager.instance.set_workspaces(connection_id, [workspace_id.to_s])

        # Sync workspace data (full or partial based on since parameter)
        since_time = safe_parse_time(since)
        result = Sync::WorkspaceSync.call(workspace_id: workspace_id, user_id: user_id, since: since_time)
        connection.write({ type: "sync", data: result }.to_json)
      end
    end
  end
end
