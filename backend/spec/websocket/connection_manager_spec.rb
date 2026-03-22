# typed: false
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

RSpec.describe Websocket::ConnectionManager do
  subject(:manager) { described_class.instance }

  # Reset the singleton state between examples
  before do
    manager.instance_variable_get(:@connections).clear
    manager.instance_variable_get(:@workspace_connections).clear
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

    it "removes workspace associations" do
      ws = FakeWebsocket.new
      workspace_id = SecureRandom.uuid
      conn_id = manager.register(ws, SecureRandom.uuid)
      manager.set_workspaces(conn_id, [workspace_id])

      manager.unregister(conn_id)

      manager.broadcast_to_workspace(workspace_id, { type: "test" })
      expect(ws.written).to be_empty
    end

    it "is a no-op for an unknown connection ID" do
      expect { manager.unregister(SecureRandom.uuid) }.not_to raise_error
    end

    it "does not log when the connection is not found" do
      expect(APP_LOGGER).not_to receive(:info).with(anything)

      manager.unregister(SecureRandom.uuid)
    end

    it "logs with the correct user ID and total when the connection is found" do
      allow(APP_LOGGER).to receive(:info)

      user_id = SecureRandom.uuid
      conn_id = manager.register(FakeWebsocket.new, user_id)
      manager.register(FakeWebsocket.new, SecureRandom.uuid) # one extra connection

      expect(APP_LOGGER).to receive(:info) do |&block|
        msg = block.call
        expect(msg).to include(user_id)
        expect(msg).to include("total: 1")
      end

      manager.unregister(conn_id)
    end
  end

  describe "#set_workspaces" do
    it "does not log when the connection is not found" do
      expect(APP_LOGGER).not_to receive(:info).with(anything)

      manager.set_workspaces(SecureRandom.uuid, [SecureRandom.uuid])
    end

    it "associates the connection with the given workspaces" do
      ws = FakeWebsocket.new
      workspace_id = SecureRandom.uuid
      conn_id = manager.register(ws, SecureRandom.uuid)
      manager.set_workspaces(conn_id, [workspace_id])

      manager.broadcast_to_workspace(workspace_id, { type: "ping" })

      expect(ws.written).to include(include("ping"))
    end

    it "replaces previous workspace associations" do
      ws = FakeWebsocket.new
      old_ws = SecureRandom.uuid
      new_ws = SecureRandom.uuid
      conn_id = manager.register(ws, SecureRandom.uuid)
      manager.set_workspaces(conn_id, [old_ws])
      manager.set_workspaces(conn_id, [new_ws])

      manager.broadcast_to_workspace(old_ws, { type: "ping" })

      expect(ws.written).to be_empty
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
  end

  describe "#broadcast_to_workspace" do
    it "writes the JSON-encoded message to each connected client" do
      ws = FakeWebsocket.new
      workspace_id = SecureRandom.uuid
      conn_id = manager.register(ws, SecureRandom.uuid)
      manager.set_workspaces(conn_id, [workspace_id])

      manager.broadcast_to_workspace(workspace_id, { type: "update", id: "123" })

      expect(ws.written).to include('{"type":"update","id":"123"}')
    end

    it "does nothing when no connections are subscribed to the workspace" do
      ws = FakeWebsocket.new
      manager.register(ws, SecureRandom.uuid)

      # No set_workspaces call — ws should never be written to.
      manager.broadcast_to_workspace(SecureRandom.uuid, { type: "ping" })

      expect(ws.written).to be_empty
    end

    context "when a write raises" do
      it "unregisters the failing connection" do
        ws = BrokenWebsocket.new
        workspace_id = SecureRandom.uuid
        conn_id = manager.register(ws, SecureRandom.uuid)
        manager.set_workspaces(conn_id, [workspace_id])

        manager.broadcast_to_workspace(workspace_id, { type: "ping" })

        expect(manager.connection_count).to eq(0)
      end

      it "does not write to the dead connection on subsequent broadcasts" do
        ws = FakeWebsocket.new
        call_count = 0
        allow(ws).to receive(:write) do
          call_count += 1
          raise StandardError, "broken pipe"
        end

        workspace_id = SecureRandom.uuid
        conn_id = manager.register(ws, SecureRandom.uuid)
        manager.set_workspaces(conn_id, [workspace_id])

        manager.broadcast_to_workspace(workspace_id, { type: "first" })
        manager.broadcast_to_workspace(workspace_id, { type: "second" })

        expect(call_count).to eq(1)
      end

      it "does not raise" do
        ws = BrokenWebsocket.new
        workspace_id = SecureRandom.uuid
        conn_id = manager.register(ws, SecureRandom.uuid)
        manager.set_workspaces(conn_id, [workspace_id])

        expect do
          manager.broadcast_to_workspace(workspace_id, { type: "ping" })
        end.not_to raise_error
      end

      it "still broadcasts to healthy connections in the same workspace" do
        broken_ws = BrokenWebsocket.new
        healthy_ws = FakeWebsocket.new
        workspace_id = SecureRandom.uuid

        conn1 = manager.register(broken_ws, SecureRandom.uuid)
        conn2 = manager.register(healthy_ws, SecureRandom.uuid)
        manager.set_workspaces(conn1, [workspace_id])
        manager.set_workspaces(conn2, [workspace_id])

        manager.broadcast_to_workspace(workspace_id, { type: "ping" })

        expect(healthy_ws.written).to include(include("ping"))
      end
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
