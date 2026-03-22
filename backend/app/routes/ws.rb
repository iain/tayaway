# typed: false
# frozen_string_literal: true

# Route files use `# typed: false` because Roda's DSL (hash_path, r.get,
# r.post, etc.) cannot be statically typed by Sorbet. This is an intentional
# exception to the project-wide `# typed: true` convention. See CLAUDE.md.

require "json"

class App
  hash_branch "ws" do |r|
    # Authenticate via single-use ticket: ws://host/ws?ticket=<jwt>
    # Optional: workspaceId and since query params for immediate workspace sync
    ticket_jwt = r.params["ticket"]
    initial_workspace_id = r.params["workspaceId"]
    initial_since = r.params["since"]

    result = Auth::ConsumeWsTicket.call(ticket_jwt: ticket_jwt)

    unless result.success?
      error_msg = result.failure.message
      r.halt [401, { "Content-Type" => "application/json" }, [{ error: error_msg }.to_json]]
    end

    user_id = result.value![:user_id]

    r.websocket do |connection|
      connection_id = Websocket::ConnectionManager.instance.register(connection, user_id)

      # Load workspaces for user
      workspaces = Workspace.for_user(user_id)
      workspace_ids = workspaces.map { |w| w.id.to_s }

      # If client requested an initial workspace, validate membership and prepare sync
      synced_workspace_id = nil
      if initial_workspace_id && workspace_ids.include?(initial_workspace_id)
        synced_workspace_id = initial_workspace_id
      end

      # Send authenticated message with workspace IDs
      auth_message = {
        type: "authenticated",
        userId: user_id.to_s,
        workspaceIds: workspace_ids
      }
      auth_message[:initialWorkspaceId] = synced_workspace_id if synced_workspace_id
      connection.write(auth_message.to_json)
      connection.write({ type: "pong", gitSha: GIT_SHA }.to_json)

      # Send workspace summaries for the workspace selector
      pool = PoolSerializer.new
      workspaces.each { |w| pool.add_workspace(w) }
      connection.write({ type: "sync", data: { objects: pool.to_a } }.to_json)

      # If we have a valid initial workspace, subscribe and sync immediately
      if synced_workspace_id
        Websocket::ConnectionManager.instance.set_workspaces(connection_id, [synced_workspace_id])
        since_time = Websocket::MessageHandler.safe_parse_time(initial_since)
        sync_result = Sync::WorkspaceSync.call(workspace_id: synced_workspace_id, since: since_time)
        connection.write({ type: "sync", data: sync_result }.to_json)
      end

      begin
        while (message = connection.read)
          Websocket::MessageHandler.handle(connection, connection_id, user_id, message.to_str)
        end
      rescue StandardError => e
        APP_LOGGER.error { "[WebSocket] Error in message loop: #{e.message}" }
      ensure
        Websocket::ConnectionManager.instance.unregister(connection_id)
      end
    end
  end
end
