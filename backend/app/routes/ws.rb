# frozen_string_literal: true

# Route files use `# typed: false` because Roda's DSL (hash_path, r.get,
# r.post, etc.) cannot be statically typed by Sorbet. This is an intentional
# exception to the project-wide `# typed: true` convention. See CLAUDE.md.

require "async"
require "async/barrier"
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
    session_id = result.value![:session_id]

    r.websocket do |connection|
      connection_id = Websocket::ConnectionManager.instance.register(connection, user_id, session_id)

      # When the client requests an initial workspace, fetch its membership
      # speculatively in parallel with the workspace list. The list is needed
      # to validate the request, but we don't have to wait for it before
      # starting the membership lookup — on the happy path we save a
      # round-trip; on the rejected path we waste a query. The barrier joins
      # both tasks at one point so a failure in either propagates cleanly and
      # neither task is orphaned if validation rejects the request.
      #
      # Note: because barrier.wait re-raises any child error, a DB failure in
      # the speculative membership lookup will fail the whole WS init even
      # when validation would have rejected the workspace anyway. That's the
      # tradeoff for the round-trip; a DB error here is loud by design.
      barrier = Async::Barrier.new
      workspaces_task = barrier.async do |task|
        task.annotate("Workspace.for_user")
        Workspace.for_user(user_id)
      end
      membership_task = if initial_workspace_id
                          barrier.async do |task|
                            task.annotate("WorkspaceMembership.find_by_workspace_and_user")
                            WorkspaceMembership.find_by_workspace_and_user(initial_workspace_id, user_id)
                          end
                        end

      barrier.wait

      workspaces = workspaces_task.wait
      workspace_ids = workspaces.map { |w| w.id.to_s }

      synced_workspace_id = nil
      synced_workspace_id = initial_workspace_id if initial_workspace_id && workspace_ids.include?(initial_workspace_id)

      # Send authenticated message with workspace IDs
      auth_message = {
        type: "authenticated",
        userId: user_id.to_s,
        workspaceIds: workspace_ids
      }
      auth_message[:initialWorkspaceId] = synced_workspace_id if synced_workspace_id
      connection.write(auth_message.to_json)
      connection.write({ type: "pong", gitSha: APP_CONFIG.git_sha }.to_json)

      # Personal sync delivers the workspace selector (workspace rows + the
      # user's own memberships across every workspace). Cross-workspace
      # personal events ride the user-audience broadcast channel and merge
      # into the same pool.
      personal_sync = Sync::PersonalSync.call(user_id: user_id)
      connection.write({ type: "sync", data: personal_sync }.to_json)

      # If we have a valid initial workspace, subscribe and sync immediately
      if synced_workspace_id
        membership = membership_task.wait
        Websocket::ConnectionManager.instance.set_workspaces(connection_id, [synced_workspace_id])
        Websocket::ConnectionManager.instance.set_membership(connection_id, membership)
        since_time = Websocket::MessageHandler.safe_parse_time(initial_since)
        sync_result = Sync::WorkspaceSync.call(workspace_id: synced_workspace_id, since: since_time, membership: membership)
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
