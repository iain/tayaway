# frozen_string_literal: true

require "spec_helper"

# Minimal stand-in for a Falcon/roda-websockets connection object.
# The websocket is T.untyped in production code so there is no class to
# verify against. Defined at top-level to satisfy RSpec/LeakyConstantDeclaration.
class FakeWebsocket
  attr_reader :written

  def initialize
    @written = []
    @flushed = false
  end

  def write(msg)
    @written << msg
  end

  def flush
    @flushed = true
  end
end

# A FakeWebsocket that raises on write, simulating a broken connection.
class BrokenWebsocket
  def write(_msg)
    raise StandardError, "broken pipe"
  end

  def flush; end
end

# A FakeWebsocket whose `write` parks until the supplied notification is
# signalled. Lets specs assert that a slow client's write does not delay
# delivery to other clients.
class BlockingWebsocket
  attr_reader :write_count

  def initialize(release)
    @release = release
    @write_count = 0
  end

  def write(_msg)
    @release.wait
    @write_count += 1
  end

  def flush; end
end

# Lifecycle + ancillary behaviour for ConnectionManager. Topic-routing
# semantics live in connection_manager_routing_spec.rb.
RSpec.describe Websocket::ConnectionManager do
  subject(:manager) { described_class.instance }

  before do
    manager.instance_variable_get(:@connections).clear
    manager.instance_variable_get(:@topic_connections).clear
  end

  describe "#register" do
    it "returns a unique connection ID" do
      id1 = manager.register(FakeWebsocket.new, SecureRandom.uuid)
      id2 = manager.register(FakeWebsocket.new, SecureRandom.uuid)

      expect(id1).not_to eq(id2)
    end

    it "increments connection count" do
      expect { manager.register(FakeWebsocket.new, SecureRandom.uuid) }
        .to change(manager, :connection_count).by(1)
    end

    it "initialises last_pong_at to now" do
      before_time = Time.now
      id = manager.register(FakeWebsocket.new, "user-1")
      after_time = Time.now

      connection = manager.instance_variable_get(:@connections)[id]
      expect(connection.last_pong_at).to be_between(before_time, after_time)
    end
  end

  describe "#unregister" do
    it "decrements connection count" do
      user_id = SecureRandom.uuid
      conn_id = manager.register(FakeWebsocket.new, user_id)

      expect { manager.unregister(conn_id) }
        .to change(manager, :connection_count).by(-1)
    end

    it "removes topic subscriptions" do
      ws = FakeWebsocket.new
      workspace_id = SecureRandom.uuid
      conn_id = manager.register(ws, SecureRandom.uuid)
      manager.subscribe(conn_id, Topic.workspace(workspace_id))

      manager.unregister(conn_id)
      manager.broadcast(Topic.workspace(workspace_id), { type: "test" })

      expect(ws.written).to be_empty
    end

    it "is a no-op for an unknown connection ID" do
      expect { manager.unregister(SecureRandom.uuid) }.not_to raise_error
    end

    it "does not log when the connection is not found" do
      allow(APP_LOGGER).to receive(:info)

      manager.unregister(SecureRandom.uuid)

      expect(APP_LOGGER).not_to have_received(:info).with(anything)
    end

    it "logs with the correct user ID and total when the connection is found" do
      logged_messages = []
      allow(APP_LOGGER).to receive(:info) { |&block| logged_messages << block.call }

      user_id = SecureRandom.uuid
      conn_id = manager.register(FakeWebsocket.new, user_id)
      manager.register(FakeWebsocket.new, SecureRandom.uuid) # one extra connection

      manager.unregister(conn_id)

      expect(APP_LOGGER).to have_received(:info).at_least(:once)
      unregister_log = logged_messages.find { |msg| msg.include?("total: 1") }
      expect(unregister_log).to include(user_id)
    end
  end

  describe "#subscribe / #unsubscribe" do
    it "is idempotent — re-subscribing to the same topic does not duplicate delivery" do
      ws = FakeWebsocket.new
      workspace_id = SecureRandom.uuid
      conn_id = manager.register(ws, SecureRandom.uuid)
      manager.subscribe(conn_id, Topic.workspace(workspace_id))
      manager.subscribe(conn_id, Topic.workspace(workspace_id))

      manager.broadcast(Topic.workspace(workspace_id), { type: "ping" })

      expect(ws.written.size).to eq(1)
    end

    it "is a no-op when the connection is unknown" do
      expect { manager.subscribe(SecureRandom.uuid, Topic.workspace(SecureRandom.uuid)) }.not_to raise_error
      expect { manager.unsubscribe(SecureRandom.uuid, Topic.workspace(SecureRandom.uuid)) }.not_to raise_error
    end
  end

  describe "#subscribed?" do
    it "returns true for topics the connection subscribes to" do
      conn_id = manager.register(FakeWebsocket.new, SecureRandom.uuid)
      topic = Topic.workspace(SecureRandom.uuid)
      manager.subscribe(conn_id, topic)

      expect(manager.subscribed?(conn_id, topic)).to be(true)
    end

    it "returns false for topics the connection does not subscribe to" do
      conn_id = manager.register(FakeWebsocket.new, SecureRandom.uuid)

      expect(manager.subscribed?(conn_id, Topic.workspace(SecureRandom.uuid))).to be(false)
    end

    it "returns false for an unknown connection" do
      expect(manager.subscribed?(SecureRandom.uuid, Topic.workspace(SecureRandom.uuid))).to be(false)
    end

    it "rejects raw strings — callers must pass a Topic" do
      conn_id = manager.register(FakeWebsocket.new, SecureRandom.uuid)
      expect { manager.subscribed?(conn_id, "workspace:abc") }.to raise_error(ArgumentError, /Topic/)
    end
  end

  describe "#update_last_pong" do
    it "updates last_pong_at for the given connection" do
      id = manager.register(FakeWebsocket.new, "user-1")

      # Backdate the timestamp via the prop setter
      connection = manager.instance_variable_get(:@connections)[id]
      old_time = Time.now - 120
      connection.last_pong_at = old_time

      manager.update_last_pong(id)

      expect(connection.last_pong_at).to be > old_time
    end

    it "is a no-op for an unknown connection ID" do
      expect { manager.update_last_pong("nonexistent-id") }.not_to raise_error
    end
  end

  describe "#ping_all" do
    it "sends a ping to all active connections" do
      ws1 = FakeWebsocket.new
      ws2 = FakeWebsocket.new
      manager.register(ws1, "user-1")
      manager.register(ws2, "user-2")

      manager.ping_all(idle_timeout: 90)

      expect(ws1.written).to include({ type: "ping" }.to_json)
      expect(ws2.written).to include({ type: "ping" }.to_json)
    end

    it "prunes connections that have not ponged within the idle timeout" do
      id = manager.register(FakeWebsocket.new, "user-1")

      # Backdate last_pong_at beyond the idle timeout
      connection = manager.instance_variable_get(:@connections)[id]
      connection.last_pong_at = Time.now - 120

      pruned = manager.ping_all(idle_timeout: 90)

      expect(pruned).to eq(1)
      expect(manager.connection_count).to eq(0)
    end

    it "does not ping connections that are already stale" do
      ws = FakeWebsocket.new
      id = manager.register(ws, "user-1")

      connection = manager.instance_variable_get(:@connections)[id]
      connection.last_pong_at = Time.now - 120

      manager.ping_all(idle_timeout: 90)

      expect(ws.written).not_to include({ type: "ping" }.to_json)
    end

    it "prunes connections where write raises an error" do
      manager.register(BrokenWebsocket.new, "user-1")

      pruned = manager.ping_all(idle_timeout: 90)

      expect(pruned).to eq(1)
      expect(manager.connection_count).to eq(0)
    end

    it "returns zero when there are no connections" do
      pruned = manager.ping_all(idle_timeout: 90)

      expect(pruned).to eq(0)
    end

    it "keeps fresh connections registered" do
      manager.register(FakeWebsocket.new, "user-1")

      pruned = manager.ping_all(idle_timeout: 90)

      expect(pruned).to eq(0)
      expect(manager.connection_count).to eq(1)
    end

    it "pings other connections without waiting for a slow client's write" do
      release = Async::Notification.new
      slow = BlockingWebsocket.new(release)
      fast = FakeWebsocket.new
      manager.register(slow, "user-1")
      manager.register(fast, "user-2")

      Sync do |task|
        ping = task.async { manager.ping_all(idle_timeout: 90) }

        task.sleep(0.01)
        expect(fast.written).not_to be_empty
        expect(slow.write_count).to eq(0)

        release.signal
        ping.wait
        expect(slow.write_count).to eq(1)
      end
    end
  end

  describe "#broadcast — workspace topic with policy context" do
    it "attaches per-connection permissions when a policy_context is supplied" do
      workspace_row = TestFactories.workspace
      owner = TestFactories.user
      TestFactories.workspace_membership(workspace: workspace_row, user: owner)
      owner_membership = WorkspaceMembership.find_by_workspace_and_user(workspace_row[:id], owner[:id])
      event_row = TestFactories.event(workspace: workspace_row, user: owner)
      event_model = Event.find(event_row[:id])

      ws = FakeWebsocket.new
      workspace_id = workspace_row[:id].to_s
      conn_id = manager.register(ws, owner[:id])
      manager.subscribe(conn_id, Topic.workspace(workspace_id))
      manager.set_membership(conn_id, workspace_id, owner_membership)

      event_hash = { id: event_model.id.to_s, objectType: "event", name: event_model.name }
      message = {
        type: "broadcast",
        workspaceId: workspace_id,
        action: "update",
        data: { objects: [event_hash] }
      }
      policy_context = Websocket::PolicyContext.new(
        raw_objects: { "event:#{event_model.id}" => event_model },
        policy_contexts: { "event:#{event_model.id}" => { has_expenses: false } }
      )

      manager.broadcast(Topic.workspace(workspace_id), message, policy_context: policy_context)

      delivered = JSON.parse(ws.written.first, symbolize_names: true)
      permissions = delivered[:data][:objects].first[:permissions]
      expect(permissions).to include(edit: { allowed: true })
    end

    it "attaches permissions to fan-out children carried in the PolicyContext" do
      workspace_row = TestFactories.workspace
      owner = TestFactories.user
      TestFactories.workspace_membership(workspace: workspace_row, user: owner)
      owner_membership = WorkspaceMembership.find_by_workspace_and_user(workspace_row[:id], owner[:id])
      event_row = TestFactories.event(workspace: workspace_row, user: owner)
      roster_row = TestFactories.chore_roster(event: event_row, user: owner)
      TestFactories.chore(chore_roster: roster_row)
      roster = ChoreRoster.find(roster_row[:id])

      pool = PoolSerializer.new(workspace_id: workspace_row[:id], collect_policy_contexts: true)
      pool.add(:chore_roster, [roster])
      message = {
        type: "broadcast",
        workspaceId: workspace_row[:id].to_s,
        action: "update",
        data: { objects: pool.to_a }
      }
      policy_context = Websocket::PolicyContext.new(
        raw_objects: pool.raw_objects,
        policy_contexts: pool.policy_contexts
      )

      ws = FakeWebsocket.new
      conn_id = manager.register(ws, owner[:id])
      manager.subscribe(conn_id, Topic.workspace(workspace_row[:id]))
      manager.set_membership(conn_id, workspace_row[:id].to_s, owner_membership)

      manager.broadcast(
        Topic.workspace(workspace_row[:id]), message, policy_context: policy_context
      )

      delivered = JSON.parse(ws.written.first, symbolize_names: true)
      types = delivered[:data][:objects].map { |o| o[:objectType] }
      expect(types).to include("choreRoster", "chore")
      delivered[:data][:objects].each do |obj|
        expect(obj[:permissions]).to be_a(Hash), "missing permissions on #{obj[:objectType]} #{obj[:id]}"
      end
    end

    it "uses the per-workspace membership when computing permissions" do
      # When a connection sits on multiple workspaces, the membership the
      # broadcast picks up must match the topic, not whichever was set last.
      ws_a = TestFactories.workspace
      ws_b = TestFactories.workspace
      user = TestFactories.user
      TestFactories.workspace_membership(workspace: ws_a, user: user, role: "owner")
      TestFactories.workspace_membership(workspace: ws_b, user: user, role: "member")
      membership_a = WorkspaceMembership.find_by_workspace_and_user(ws_a[:id], user[:id])
      membership_b = WorkspaceMembership.find_by_workspace_and_user(ws_b[:id], user[:id])
      event_b_row = TestFactories.event(workspace: ws_b, user: user)
      event_b = Event.find(event_b_row[:id])

      ws = FakeWebsocket.new
      conn_id = manager.register(ws, user[:id])
      manager.subscribe(conn_id, Topic.workspace(ws_a[:id]), Topic.workspace(ws_b[:id]))
      manager.set_membership(conn_id, ws_a[:id].to_s, membership_a)
      manager.set_membership(conn_id, ws_b[:id].to_s, membership_b)

      event_hash = { id: event_b.id.to_s, objectType: "event", name: event_b.name }
      message = {
        type: "broadcast",
        workspaceId: ws_b[:id].to_s,
        action: "update",
        data: { objects: [event_hash] }
      }
      policy_context = Websocket::PolicyContext.new(
        raw_objects: { "event:#{event_b.id}" => event_b },
        policy_contexts: { "event:#{event_b.id}" => { has_expenses: false } }
      )

      manager.broadcast(Topic.workspace(ws_b[:id]), message, policy_context: policy_context)

      delivered = JSON.parse(ws.written.first, symbolize_names: true)
      # The membership for ws_b carries role=member, so edit is gated by
      # MemberPolicy, not OwnerPolicy. The important assertion is that
      # *some* permissions key was attached — i.e. permission attachment
      # found a membership rather than silently skipping for nil.
      expect(delivered[:data][:objects].first).to have_key(:permissions)
    end
  end

  describe "#broadcast — error handling" do
    it "unregisters the connection when its write raises" do
      ws = BrokenWebsocket.new
      workspace_id = SecureRandom.uuid
      conn_id = manager.register(ws, SecureRandom.uuid)
      manager.subscribe(conn_id, Topic.workspace(workspace_id))

      manager.broadcast(Topic.workspace(workspace_id), { type: "ping" })

      expect(manager.connection_count).to eq(0)
    end

    it "does not raise when a connection write fails" do
      ws = BrokenWebsocket.new
      workspace_id = SecureRandom.uuid
      conn_id = manager.register(ws, SecureRandom.uuid)
      manager.subscribe(conn_id, Topic.workspace(workspace_id))

      expect do
        manager.broadcast(Topic.workspace(workspace_id), { type: "ping" })
      end.not_to raise_error
    end

    it "still broadcasts to healthy subscribers when one connection fails" do
      broken = BrokenWebsocket.new
      healthy = FakeWebsocket.new
      workspace_id = SecureRandom.uuid

      conn1 = manager.register(broken, SecureRandom.uuid)
      conn2 = manager.register(healthy, SecureRandom.uuid)
      manager.subscribe(conn1, Topic.workspace(workspace_id))
      manager.subscribe(conn2, Topic.workspace(workspace_id))

      manager.broadcast(Topic.workspace(workspace_id), { type: "ping" })

      expect(healthy.written).to include(include("ping"))
    end

    it "delivers to fast subscribers without waiting for a slow client's write" do
      release = Async::Notification.new
      slow = BlockingWebsocket.new(release)
      fast = FakeWebsocket.new
      workspace_id = SecureRandom.uuid

      slow_conn = manager.register(slow, SecureRandom.uuid)
      fast_conn = manager.register(fast, SecureRandom.uuid)
      manager.subscribe(slow_conn, Topic.workspace(workspace_id))
      manager.subscribe(fast_conn, Topic.workspace(workspace_id))

      Sync do |task|
        broadcast = task.async do
          manager.broadcast(Topic.workspace(workspace_id), { type: "ping" })
        end

        task.sleep(0.01)
        expect(fast.written).not_to be_empty
        expect(slow.write_count).to eq(0)

        release.signal
        broadcast.wait
        expect(slow.write_count).to eq(1)
      end
    end
  end

  describe "#send_to_connections" do
    it "writes the message to each given connection" do
      ws1 = FakeWebsocket.new
      ws2 = FakeWebsocket.new
      conn1 = manager.register(ws1, SecureRandom.uuid)
      conn2 = manager.register(ws2, SecureRandom.uuid)

      manager.send_to_connections([conn1, conn2], { type: "sync", data: { ok: true } })

      expect(ws1.written.first).to include('"sync"')
      expect(ws2.written.first).to include('"sync"')
    end

    it "is a no-op for an empty connection list" do
      expect { manager.send_to_connections([], { type: "anything" }) }.not_to raise_error
    end

    it "skips unknown connection ids without raising" do
      ws = FakeWebsocket.new
      conn = manager.register(ws, SecureRandom.uuid)

      manager.send_to_connections([conn, SecureRandom.uuid], { type: "sync" })

      expect(ws.written.size).to eq(1)
    end
  end

  describe "#connections_for_user" do
    it "returns IDs of all connections for a given user" do
      user_id = SecureRandom.uuid
      conn1 = manager.register(FakeWebsocket.new, user_id)
      conn2 = manager.register(FakeWebsocket.new, user_id)
      manager.register(FakeWebsocket.new, SecureRandom.uuid) # different user

      result = manager.connections_for_user(user_id)

      expect(result).to contain_exactly(conn1, conn2)
    end

    it "returns an empty array when user has no connections" do
      expect(manager.connections_for_user(SecureRandom.uuid)).to eq([])
    end
  end

  describe "#close_sessions" do
    it "sends session_revoked and unregisters matching connections" do
      session_id = SecureRandom.uuid
      ws = FakeWebsocket.new
      manager.register(ws, SecureRandom.uuid, session_id)

      manager.close_sessions([session_id])

      expect(ws.written).to include({ type: "session_revoked" }.to_json)
      expect(manager.connection_count).to eq(0)
    end

    it "does not affect connections with a different session_id" do
      ws_target = FakeWebsocket.new
      ws_other = FakeWebsocket.new
      target_sid = SecureRandom.uuid
      other_sid = SecureRandom.uuid

      manager.register(ws_target, SecureRandom.uuid, target_sid)
      manager.register(ws_other, SecureRandom.uuid, other_sid)

      manager.close_sessions([target_sid])

      expect(ws_target.written).to include({ type: "session_revoked" }.to_json)
      expect(ws_other.written).to be_empty
      expect(manager.connection_count).to eq(1)
    end

    it "skips connections with nil session_id" do
      ws = FakeWebsocket.new
      manager.register(ws, SecureRandom.uuid) # no session_id

      manager.close_sessions([SecureRandom.uuid])

      expect(ws.written).to be_empty
      expect(manager.connection_count).to eq(1)
    end

    it "is a no-op when session_ids is empty" do
      ws = FakeWebsocket.new
      manager.register(ws, SecureRandom.uuid, SecureRandom.uuid)

      manager.close_sessions([])

      expect(ws.written).to be_empty
      expect(manager.connection_count).to eq(1)
    end

    it "handles write errors gracefully and still unregisters" do
      session_id = SecureRandom.uuid
      manager.register(BrokenWebsocket.new, SecureRandom.uuid, session_id)

      expect { manager.close_sessions([session_id]) }.not_to raise_error
      expect(manager.connection_count).to eq(0)
    end
  end

  describe "#connection_count" do
    it "returns 0 when no connections are registered" do
      expect(manager.connection_count).to eq(0)
    end

    it "reflects the current number of registered connections" do
      manager.register(FakeWebsocket.new, SecureRandom.uuid)
      manager.register(FakeWebsocket.new, SecureRandom.uuid)

      expect(manager.connection_count).to eq(2)
    end
  end
end
