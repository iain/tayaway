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

    client_version = r.params["v"]

    r.websocket do |connection|
      # Protocol version gate. Mostly belt-and-braces — an outdated client
      # normally gets its 426 fetching the ws-ticket — but this catches the
      # race where a ticket minted just before a deploy is redeemed just
      # after. A typed message (not a bare close code) because the client
      # treats unexplained closes as reconnectable network failures.
      unless ClientProtocol.supported?(client_version)
        connection.write(
          {
            type: "update_required",
            minSupportedVersion: ClientProtocol::MIN_SUPPORTED_VERSION
          }.to_json
        )
        connection.close
        next
      end

      connection_id = Websocket::ConnectionManager.instance.register(connection, user_id, session_id)

      # Fetch every workspace the user belongs to AND every membership in one
      # parallel pass. We need both at auth: workspace_ids to populate the
      # auth message and validate the requested initial workspace; memberships
      # to drive per-workspace permission attachment on broadcasts. Issuing
      # them under one barrier lets failures propagate cleanly without
      # orphaning tasks.
      barrier = Async::Barrier.new
      workspaces_task = barrier.async do |task|
        task.annotate("Workspace.for_user")
        Workspace.for_user(user_id)
      end
      memberships_task = barrier.async do |task|
        task.annotate("WorkspaceMembership.for_user")
        WorkspaceMembership.for_user(user_id)
      end

      barrier.wait

      workspaces = workspaces_task.wait
      memberships = memberships_task.wait
      workspace_ids = workspaces.map { |w| w.id.to_s }
      memberships_by_workspace = memberships.each_with_object({}) { |m, h| h[m.workspace_id.to_s] = m }

      synced_workspace_id = nil
      synced_workspace_id = initial_workspace_id if initial_workspace_id && workspace_ids.include?(initial_workspace_id)

      # Subscribe to every topic this user cares about: their own user
      # channel (for notifications) plus every workspace they're a member
      # of (so cross-workspace broadcasts arrive in real time, not just
      # when they switch). Memberships are stored per-workspace so
      # permission attachment picks the right one for each broadcast.
      manager = Websocket::ConnectionManager.instance
      topics = [Topic.user(user_id)] + workspace_ids.map { |id| Topic.workspace(id) }
      manager.subscribe(connection_id, *topics)
      memberships.each do |membership|
        manager.set_membership(connection_id, membership.workspace_id.to_s, membership)
      end

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
      # user's own memberships across every workspace) plus the recent
      # notification backlog. Cross-workspace personal events ride the user
      # topic and merge into the same pool. Pass the already-loaded
      # workspaces + memberships through to avoid duplicate queries.
      personal_sync = Sync::PersonalSync.call(
        user_id: user_id, workspaces: workspaces, memberships: memberships
      )
      connection.write({ type: "sync", data: personal_sync }.to_json)

      # If we have a valid initial workspace, send its workspace-scoped sync.
      # Subscription is already in place from the bulk subscribe above.
      if synced_workspace_id
        membership = memberships_by_workspace[synced_workspace_id]
        since_time = Websocket::MessageHandler.safe_parse_time(initial_since)
        sync_result = Sync::WorkspaceSync.call(workspace_id: synced_workspace_id, since: since_time, membership: membership)
        connection.write({ type: "sync", data: sync_result }.to_json)
      end

      begin
        while (message = connection.read)
          Websocket::MessageHandler.handle(connection, connection_id, user_id, message.to_str)
        end
      rescue IOError => e
        # Expected when the server closes the connection itself (idle prune,
        # session revocation, shutdown) — the parked read raises "closed
        # stream". Not a client error, so keep it out of the error log.
        APP_LOGGER.debug { "[WebSocket] Message loop ended: #{e.message}" }
      rescue StandardError => e
        APP_LOGGER.error { "[WebSocket] Error in message loop: #{e.message}" }
      ensure
        Websocket::ConnectionManager.instance.unregister(connection_id)
      end
    end
  end
end
