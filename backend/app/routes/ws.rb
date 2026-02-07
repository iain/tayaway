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

      # Send authenticated message
      connection.write({ type: "authenticated", userId: user_id.to_s }.to_json)

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

  def handle_message(connection, connection_id, user_id, raw_message)
    data = JSON.parse(raw_message, symbolize_names: true)
    type = data[:type]

    case type
    when "subscribe"
      handle_subscribe(connection, connection_id, user_id, data[:channel])
    when "unsubscribe"
      handle_unsubscribe(connection, connection_id, data[:channel])
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

  def handle_subscribe(connection, connection_id, user_id, channel)
    unless channel&.include?(":")
      connection.write({ type: "error", message: "Invalid channel format. Expected {objectType}:{id}" }.to_json)
      return
    end

    object_type, object_id = channel.split(":", 2)

    # Verify object type is supported
    unless Websocket::Listener.type_config(object_type)
      connection.write({ type: "error", message: "Unknown object type: #{object_type}" }.to_json)
      return
    end

    # Verify object exists
    object = Websocket::Listener.find_object(object_type, object_id)
    unless object
      connection.write({ type: "error", message: "#{object_type.capitalize} not found" }.to_json)
      return
    end

    Websocket::ConnectionManager.instance.subscribe(connection_id, channel)
    connection.write({ type: "subscribed", channel: channel }.to_json)
  end

  def handle_unsubscribe(connection, connection_id, channel)
    unless channel
      connection.write({ type: "error", message: "Channel is required" }.to_json)
      return
    end

    Websocket::ConnectionManager.instance.unsubscribe(connection_id, channel)
    connection.write({ type: "unsubscribed", channel: channel }.to_json)
  end
end
