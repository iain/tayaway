# frozen_string_literal: true

require "spec_helper"

RSpec.describe Websocket::Listener do
  describe ".handle_notification" do
    let(:workspace) { TestFactories.workspace }
    let(:user) { TestFactories.user }
    let(:manager) { instance_double(Websocket::ConnectionManager, broadcast_to_workspace: nil) }

    def invoke(payload)
      described_class.handle_notification(payload.to_json, manager)
    end

    it "threads a PolicyContext built from the pool into the broadcast" do
      event_row = TestFactories.event(workspace: workspace, user: user)

      captured = nil
      allow(manager).to receive(:broadcast_to_workspace) do |_ws, _msg, policy_context:|
        captured = policy_context
      end

      invoke(
        workspaceId: workspace[:id].to_s,
        objectType: "event",
        objectId: event_row[:id].to_s,
        action: "update"
      )

      expect(captured).to be_a(Websocket::PolicyContext)
      # raw_objects and policy_contexts are keyed by "<registry_key>:<id>" so
      # fan-out children can be looked up alongside the primary object.
      expect(captured.raw_objects).to have_key("event:#{event_row[:id]}")
      expect(captured.policy_contexts).to have_key("event:#{event_row[:id]}")
      expect(captured.policy_contexts["event:#{event_row[:id]}"]).to include(has_expenses: false)
    end

    it "broadcasts a deleted marker when an update notify loses the race to a delete" do
      ghost_id = SecureRandom.uuid
      captured_msg = nil
      allow(manager).to receive(:broadcast_to_workspace) do |_ws, msg, **_|
        captured_msg = msg
      end

      invoke(
        workspaceId: workspace[:id].to_s,
        objectType: "event",
        objectId: ghost_id,
        action: "update"
      )

      expect(captured_msg[:action]).to eq("delete")
      expect(captured_msg[:data][:deleted].first).to include(objectType: "event", id: ghost_id)
    end

    it "broadcasts a deleted marker for explicit delete notifications" do
      event_row = TestFactories.event(workspace: workspace, user: user)
      captured_msg = nil
      allow(manager).to receive(:broadcast_to_workspace) do |_ws, msg, **_|
        captured_msg = msg
      end

      invoke(
        workspaceId: workspace[:id].to_s,
        objectType: "event",
        objectId: event_row[:id].to_s,
        action: "delete"
      )

      expect(captured_msg[:action]).to eq("delete")
      expect(captured_msg[:data][:deleted].first).to include(objectType: "event", id: event_row[:id].to_s)
    end

    it "logs and drops notifications for unknown object types" do
      allow(APP_LOGGER).to receive(:warn)

      invoke(
        workspaceId: workspace[:id].to_s,
        objectType: "not_a_real_type",
        objectId: SecureRandom.uuid,
        action: "update"
      )

      expect(APP_LOGGER).to have_received(:warn)
      expect(manager).not_to have_received(:broadcast_to_workspace)
    end

    it "logs and drops malformed JSON without raising" do
      allow(APP_LOGGER).to receive(:error)

      expect { described_class.handle_notification("not-json", manager) }.not_to raise_error
      expect(APP_LOGGER).to have_received(:error)
    end
  end
end
