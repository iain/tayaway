# typed: false
# frozen_string_literal: true

require "json"

class App
  hash_branch "ws" do |r|
    # Authenticate via query param: ws://host/ws?token=session_token
    token = r.params["token"]

    unless token
      r.halt [401, { "Content-Type" => "application/json" }, ['{"error":"Missing token"}']]
    end

    session = Session.find_valid(token)

    unless session
      r.halt [401, { "Content-Type" => "application/json" }, ['{"error":"Invalid or expired token"}']]
    end

    user_id = session.user_id

    r.websocket do |connection|
      connection_id = Websocket::ConnectionManager.instance.register(connection, user_id)

      # Load workspaces for user and set up workspace subscriptions
      workspaces = Workspace.for_user(user_id)
      workspace_ids = workspaces.map { |w| w.id.to_s }
      Websocket::ConnectionManager.instance.set_workspaces(connection_id, workspace_ids)

      # Send authenticated message with workspace IDs
      connection.write({ type: "authenticated", userId: user_id.to_s, workspaceIds: workspace_ids }.to_json)

      # Build and send initial sync with all workspace data
      pool = PoolSerializer.new
      workspaces.each { |w| pool.add_workspace_with_events(w) }
      connection.write({ type: "sync", data: { objects: pool.to_a } }.to_json)

      begin
        while (message = connection.read)
          handle_message(connection, connection_id, user_id, message)
        end
      rescue StandardError => e
        warn "[WebSocket] Error in message loop: #{e.message}"
      ensure
        Websocket::ConnectionManager.instance.unregister(connection_id)
      end
    end
  end

  private

  def handle_message(connection, _connection_id, _user_id, raw_message)
    data = JSON.parse(raw_message, symbolize_names: true)
    type = data[:type]

    case type
    when "ping"
      connection.write({ type: "pong" }.to_json)
    else
      connection.write({ type: "error", message: "Unknown message type" }.to_json)
    end
  rescue JSON::ParserError
    connection.write({ type: "error", message: "Invalid JSON" }.to_json)
  rescue StandardError => e
    connection.write({ type: "error", message: e.message }.to_json)
  end
end
