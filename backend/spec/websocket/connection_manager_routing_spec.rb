# frozen_string_literal: true

require "spec_helper"

# Behaviour-shaped routing spec for ConnectionManager. The sibling
# connection_manager_spec.rb covers ancillary concerns (ping/keepalive,
# write-error pruning, slow-client isolation, session_revoked); this file
# pins the *routing contract* the planned topic/subscription refactor must
# preserve.
#
# All transport-shape coupling is funnelled through the helpers at the
# top — `subscribe_to_workspace`, `send_to_workspace`, etc. The body of
# every example describes outcomes, not method names, so when the manager
# is swapped to a `subscribe(conn, topic)` / `broadcast(topic, msg)` API
# only the helpers need to change.
class RoutingFakeWebsocket
  attr_reader :written

  def initialize
    @written = []
  end

  def write(msg)
    @written << msg
  end

  def flush; end
end

RSpec.describe Websocket::ConnectionManager do
  subject(:manager) { described_class.instance }

  before do
    manager.instance_variable_get(:@connections).clear
    manager.instance_variable_get(:@topic_connections).clear
  end

  # ------------------------------------------------------------------
  # Helpers — the only place the API surface is named. Routing examples
  # below describe outcomes, not method names; if the underlying
  # primitive moves again, only these helpers need to change.
  # ------------------------------------------------------------------

  def register(websocket, user_id: SecureRandom.uuid)
    conn_id = manager.register(websocket, user_id)
    # The connection always subscribes to its own user topic — same
    # behaviour as the production auth handshake.
    manager.subscribe(conn_id, Topic.user(user_id))
    [conn_id, user_id]
  end

  def subscribe_to_workspace(conn_id, workspace_id)
    manager.subscribe(conn_id, Topic.workspace(workspace_id))
  end

  def unsubscribe_all_workspaces(conn_id)
    conn = manager.instance_variable_get(:@connections)[conn_id]
    return unless conn

    workspace_topics = conn.topics.select(&:workspace?)
    manager.unsubscribe(conn_id, *workspace_topics)
  end

  def send_to_workspace(workspace_id, message)
    manager.broadcast(Topic.workspace(workspace_id), message)
  end

  def send_to_user(user_id, message)
    manager.broadcast(Topic.user(user_id), message)
  end

  def received?(websocket, fragment)
    websocket.written.any? { |msg| msg.include?(fragment) }
  end

  # ------------------------------------------------------------------
  # Workspace routing
  # ------------------------------------------------------------------

  describe "workspace routing" do
    it "delivers a workspace message to connections that asked to hear about that workspace" do
      ws = RoutingFakeWebsocket.new
      workspace_id = SecureRandom.uuid
      conn_id, = register(ws)
      subscribe_to_workspace(conn_id, workspace_id)

      send_to_workspace(workspace_id, { type: "broadcast", id: "evt-1" })

      expect(received?(ws, "evt-1")).to be(true)
    end

    it "does not deliver a workspace message to connections that did not ask for that workspace" do
      uninterested = RoutingFakeWebsocket.new
      register(uninterested)

      send_to_workspace(SecureRandom.uuid, { type: "broadcast" })

      expect(uninterested.written).to be_empty
    end

    it "delivers the same workspace message to every connection that asked for it" do
      ws1 = RoutingFakeWebsocket.new
      ws2 = RoutingFakeWebsocket.new
      workspace_id = SecureRandom.uuid
      conn1, = register(ws1)
      conn2, = register(ws2)
      subscribe_to_workspace(conn1, workspace_id)
      subscribe_to_workspace(conn2, workspace_id)

      send_to_workspace(workspace_id, { type: "broadcast", id: "shared" })

      expect(received?(ws1, "shared")).to be(true)
      expect(received?(ws2, "shared")).to be(true)
    end

    it "delivers messages to a connection that is subscribed to several workspaces at once" do
      # Auto-subscription at auth means a connection sits on every
      # workspace its user is a member of. Each workspace's broadcasts
      # must still reach that connection independently.
      ws = RoutingFakeWebsocket.new
      ws_a = SecureRandom.uuid
      ws_b = SecureRandom.uuid
      conn_id, = register(ws)
      subscribe_to_workspace(conn_id, ws_a)
      subscribe_to_workspace(conn_id, ws_b)

      send_to_workspace(ws_a, { type: "broadcast", id: "a-msg" })
      send_to_workspace(ws_b, { type: "broadcast", id: "b-msg" })

      expect(received?(ws, "a-msg")).to be(true)
      expect(received?(ws, "b-msg")).to be(true)
    end

    it "stops delivering to a connection that explicitly unsubscribed from every workspace" do
      ws = RoutingFakeWebsocket.new
      workspace_id = SecureRandom.uuid
      conn_id, = register(ws)
      subscribe_to_workspace(conn_id, workspace_id)
      unsubscribe_all_workspaces(conn_id)

      send_to_workspace(workspace_id, { type: "broadcast" })

      expect(ws.written).to be_empty
    end
  end

  # ------------------------------------------------------------------
  # User routing
  # ------------------------------------------------------------------

  describe "user routing" do
    it "delivers a per-user message to every connection of that user" do
      ws1 = RoutingFakeWebsocket.new
      ws2 = RoutingFakeWebsocket.new
      user_id = SecureRandom.uuid
      register(ws1, user_id: user_id)
      register(ws2, user_id: user_id)

      send_to_user(user_id, { type: "broadcast", id: "u1" })

      expect(received?(ws1, "u1")).to be(true)
      expect(received?(ws2, "u1")).to be(true)
    end

    it "does not deliver a per-user message to connections of other users" do
      target_ws = RoutingFakeWebsocket.new
      other_ws = RoutingFakeWebsocket.new
      target_user = SecureRandom.uuid
      register(target_ws, user_id: target_user)
      register(other_ws, user_id: SecureRandom.uuid)

      send_to_user(target_user, { type: "broadcast", id: "u-only" })

      expect(received?(target_ws, "u-only")).to be(true)
      expect(other_ws.written).to be_empty
    end

    it "delivers per-user messages regardless of which workspace the connection currently has open" do
      # The cross-workspace receipt invariant: if a per-user event fires
      # while the recipient is sitting in a different workspace, their
      # connection still gets the message. This is what makes notification
      # delivery, role-change badges, and invite-accepts work when the
      # user is "elsewhere".
      ws = RoutingFakeWebsocket.new
      user_id = SecureRandom.uuid
      conn_id, = register(ws, user_id: user_id)
      subscribe_to_workspace(conn_id, SecureRandom.uuid) # some unrelated workspace

      send_to_user(user_id, { type: "broadcast", id: "cross-ws" })

      expect(received?(ws, "cross-ws")).to be(true)
    end
  end

  # ------------------------------------------------------------------
  # Unregister cleans up every routing association
  # ------------------------------------------------------------------

  describe "unregister" do
    it "stops workspace messages from reaching the connection" do
      ws = RoutingFakeWebsocket.new
      workspace_id = SecureRandom.uuid
      conn_id, = register(ws)
      subscribe_to_workspace(conn_id, workspace_id)

      manager.unregister(conn_id)
      send_to_workspace(workspace_id, { type: "broadcast" })

      expect(ws.written).to be_empty
    end

    it "stops per-user messages from reaching the connection" do
      ws = RoutingFakeWebsocket.new
      user_id = SecureRandom.uuid
      conn_id, = register(ws, user_id: user_id)

      manager.unregister(conn_id)
      send_to_user(user_id, { type: "broadcast" })

      expect(ws.written).to be_empty
    end
  end
end
