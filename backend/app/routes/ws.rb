# typed: false
# frozen_string_literal: true

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
      r.halt [401, { "Content-Type" => "application/json" }, ["{\"error\":\"#{error_msg}\"}"]]
    end

    user_id = result.value![:user_id]

    r.websocket do |connection|
      connection_id = Websocket::ConnectionManager.instance.register(connection, user_id)

      # Load workspaces and memberships for user
      workspaces = Workspace.for_user(user_id)
      workspace_ids = workspaces.map { |w| w.id.to_s }
      memberships = WorkspaceMembership.for_user(user_id).map do |m|
        { workspaceId: m.workspace_id.to_s, memberId: m.id.to_s }
      end

      # If client requested an initial workspace, validate membership and prepare sync
      synced_workspace_id = nil
      if initial_workspace_id && workspace_ids.include?(initial_workspace_id)
        synced_workspace_id = initial_workspace_id
      end

      # Send authenticated message with workspace IDs and memberships
      auth_message = {
        type: "authenticated",
        userId: user_id.to_s,
        workspaceIds: workspace_ids,
        memberships: memberships
      }
      auth_message[:initialWorkspaceId] = synced_workspace_id if synced_workspace_id
      connection.write(auth_message.to_json)

      # Send workspace summaries for the workspace selector
      pool = PoolSerializer.new
      workspaces.each { |w| pool.add_workspace(w) }
      connection.write({ type: "sync", data: { objects: pool.to_a } }.to_json)

      # If we have a valid initial workspace, subscribe and sync immediately
      if synced_workspace_id
        Websocket::ConnectionManager.instance.set_workspaces(connection_id, [synced_workspace_id])
        since_time = initial_since ? Time.parse(initial_since) : nil
        sync_result = Sync::WorkspaceSync.call(workspace_id: synced_workspace_id, since: since_time)
        connection.write({ type: "sync", data: sync_result }.to_json)
      end

      begin
        while (message = connection.read)
          handle_message(connection, connection_id, user_id, message)
        end
      rescue StandardError => e
        APP_LOGGER.error { "[WebSocket] Error in message loop: #{e.message}" }
      ensure
        Websocket::ConnectionManager.instance.unregister(connection_id)
      end
    end
  end

  private

  def handle_message(connection, connection_id, user_id, raw_message)
    data = JSON.parse(raw_message, symbolize_names: true)
    type = data[:type]

    case type
    when "ping"
      connection.write({ type: "pong" }.to_json)
    when "switch_workspace"
      handle_switch_workspace(connection, connection_id, user_id, data[:workspaceId], data[:since])
    else
      connection.write({ type: "error", message: "Unknown message type" }.to_json)
    end
  rescue JSON::ParserError
    connection.write({ type: "error", message: "Invalid JSON" }.to_json)
  rescue StandardError => e
    connection.write({ type: "error", message: e.message }.to_json)
  end

  def handle_switch_workspace(connection, connection_id, user_id, workspace_id, since = nil)
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
    since_time = since ? Time.parse(since) : nil
    result = Sync::WorkspaceSync.call(workspace_id: workspace_id, since: since_time)
    connection.write({ type: "sync", data: result }.to_json)
  end
end
