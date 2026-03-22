# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Websocket::ConnectionManager do
  subject(:manager) { described_class.instance }

  # Reset singleton state between tests so each example starts clean.
  before do
    manager.instance_variable_set(:@connections, {})
    manager.instance_variable_set(:@workspace_connections, {})
  end

  define_method(:fake_websocket) do
    double("websocket", write: nil, flush: nil) # rubocop:disable RSpec/VerifiedDoubles
  end

  describe "#register" do
    it "returns a unique connection ID" do
      ws = fake_websocket
      id1 = manager.register(ws, SecureRandom.uuid)
      id2 = manager.register(ws, SecureRandom.uuid)

      expect(id1).not_to eq(id2)
    end

    it "increments connection count" do
      expect { manager.register(fake_websocket, SecureRandom.uuid) }
        .to change(manager, :connection_count).by(1)
    end
  end

  describe "#unregister" do
    it "decrements connection count" do
      user_id = SecureRandom.uuid
      conn_id = manager.register(fake_websocket, user_id)

      expect { manager.unregister(conn_id) }
        .to change(manager, :connection_count).by(-1)
    end

    it "removes workspace associations" do
      ws = fake_websocket
      workspace_id = SecureRandom.uuid
      conn_id = manager.register(ws, SecureRandom.uuid)
      manager.set_workspaces(conn_id, [workspace_id])

      manager.unregister(conn_id)

      allow(ws).to receive(:write)
      allow(ws).to receive(:flush)
      manager.broadcast_to_workspace(workspace_id, { type: "test" })
      expect(ws).not_to have_received(:write)
    end

    it "is a no-op for an unknown connection ID" do
      expect { manager.unregister(SecureRandom.uuid) }.not_to raise_error
    end
  end

  describe "#set_workspaces" do
    it "associates the connection with the given workspaces" do
      ws = fake_websocket
      workspace_id = SecureRandom.uuid
      conn_id = manager.register(ws, SecureRandom.uuid)
      manager.set_workspaces(conn_id, [workspace_id])

      manager.broadcast_to_workspace(workspace_id, { type: "ping" })

      expect(ws).to have_received(:write).with(include("ping"))
    end

    it "replaces previous workspace associations" do
      ws = fake_websocket
      old_ws = SecureRandom.uuid
      new_ws = SecureRandom.uuid
      conn_id = manager.register(ws, SecureRandom.uuid)
      manager.set_workspaces(conn_id, [old_ws])
      manager.set_workspaces(conn_id, [new_ws])

      manager.broadcast_to_workspace(old_ws, { type: "ping" })

      expect(ws).not_to have_received(:write)
    end
  end

  describe "#broadcast_to_workspace" do
    it "writes the JSON-encoded message to each connected client" do
      ws = fake_websocket
      workspace_id = SecureRandom.uuid
      conn_id = manager.register(ws, SecureRandom.uuid)
      manager.set_workspaces(conn_id, [workspace_id])

      manager.broadcast_to_workspace(workspace_id, { type: "update", id: "123" })

      expect(ws).to have_received(:write).with('{"type":"update","id":"123"}')
    end

    it "does nothing when no connections are subscribed to the workspace" do
      ws = fake_websocket
      manager.register(ws, SecureRandom.uuid)

      # No set_workspaces call — ws should never be written to.
      manager.broadcast_to_workspace(SecureRandom.uuid, { type: "ping" })

      expect(ws).not_to have_received(:write)
    end

    context "when a write raises" do
      it "unregisters the failing connection" do
        ws = fake_websocket
        allow(ws).to receive(:write).and_raise(StandardError, "broken pipe")

        workspace_id = SecureRandom.uuid
        conn_id = manager.register(ws, SecureRandom.uuid)
        manager.set_workspaces(conn_id, [workspace_id])

        manager.broadcast_to_workspace(workspace_id, { type: "ping" })

        expect(manager.connection_count).to eq(0)
      end

      it "does not write to the dead connection on subsequent broadcasts" do
        ws = fake_websocket
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
        ws = fake_websocket
        allow(ws).to receive(:write).and_raise(StandardError, "broken pipe")

        workspace_id = SecureRandom.uuid
        conn_id = manager.register(ws, SecureRandom.uuid)
        manager.set_workspaces(conn_id, [workspace_id])

        expect do
          manager.broadcast_to_workspace(workspace_id, { type: "ping" })
        end.not_to raise_error
      end

      it "still broadcasts to healthy connections in the same workspace" do
        broken_ws = fake_websocket
        allow(broken_ws).to receive(:write).and_raise(StandardError, "broken pipe")

        healthy_ws = fake_websocket
        workspace_id = SecureRandom.uuid

        conn1 = manager.register(broken_ws, SecureRandom.uuid)
        conn2 = manager.register(healthy_ws, SecureRandom.uuid)
        manager.set_workspaces(conn1, [workspace_id])
        manager.set_workspaces(conn2, [workspace_id])

        manager.broadcast_to_workspace(workspace_id, { type: "ping" })

        expect(healthy_ws).to have_received(:write).with(include("ping"))
      end
    end
  end

  describe "#connections_for_user" do
    it "returns IDs of all connections for a given user" do
      user_id = SecureRandom.uuid
      conn1 = manager.register(fake_websocket, user_id)
      conn2 = manager.register(fake_websocket, user_id)
      manager.register(fake_websocket, SecureRandom.uuid) # different user

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
      manager.register(fake_websocket, SecureRandom.uuid)
      manager.register(fake_websocket, SecureRandom.uuid)

      expect(manager.connection_count).to eq(2)
    end
  end
end
