# frozen_string_literal: true

require "spec_helper"

RSpec.describe Websocket::Listener do
  describe ".handle_notification" do
    let(:workspace) { TestFactories.workspace }
    let(:user) { TestFactories.user }
    let(:manager) do
      instance_double(
        Websocket::ConnectionManager,
        broadcast_to_workspace: nil,
        broadcast_to_user: nil
      )
    end

    def invoke(payload)
      described_class.handle_notification(payload.to_json, manager)
    end

    context "with update payloads (no audience inline — Listener derives it from the loaded object)" do
      it "threads a PolicyContext built from the pool into the workspace broadcast" do
        event_row = TestFactories.event(workspace: workspace, user: user)

        captured = nil
        allow(manager).to receive(:broadcast_to_workspace) do |_ws, _msg, policy_context:|
          captured = policy_context
        end

        invoke(
          objectType: "event",
          objectId: event_row[:id].to_s,
          action: "update"
        )

        expect(captured).to be_a(Websocket::PolicyContext)
        expect(captured.raw_objects).to have_key("event:#{event_row[:id]}")
        expect(captured.policy_contexts).to have_key("event:#{event_row[:id]}")
        expect(captured.policy_contexts["event:#{event_row[:id]}"]).to include(has_expenses: false)
      end

      it "drops the update when the object is gone — the corresponding delete NOTIFY handles cleanup" do
        ghost_id = SecureRandom.uuid

        invoke(
          objectType: "event",
          objectId: ghost_id,
          action: "update"
        )

        expect(manager).not_to have_received(:broadcast_to_workspace)
        expect(manager).not_to have_received(:broadcast_to_user)
      end

      it "fans a member update out to both the workspace and the affected user" do
        membership_row = TestFactories.workspace_membership(workspace: workspace, user: user, role: "member")

        ws_captured = nil
        user_captured = nil
        allow(manager).to receive(:broadcast_to_workspace) do |ws_id, msg, **_|
          ws_captured = [ws_id, msg]
        end
        allow(manager).to receive(:broadcast_to_user) do |uid, msg|
          user_captured = [uid, msg]
        end

        invoke(
          objectType: "member",
          objectId: membership_row[:id],
          action: "update"
        )

        expect(ws_captured&.first).to eq(workspace[:id].to_s)
        expect(ws_captured&.last&.dig(:data, :objects, 0)).to include(
          objectType: "member",
          id: membership_row[:id]
        )
        expect(user_captured&.first).to eq(user[:id].to_s)
        expect(user_captured&.last&.dig(:data, :objects, 0)).to include(
          objectType: "member",
          id: membership_row[:id],
          workspaceId: workspace[:id].to_s
        )
      end

      it "broadcasts a notification to its user channel" do
        notification = TestFactories.notification(user: user, workspace: workspace)

        captured_user_id = nil
        captured_msg = nil
        allow(manager).to receive(:broadcast_to_user) do |uid, msg|
          captured_user_id = uid
          captured_msg = msg
        end

        invoke(
          objectType: "notification",
          objectId: notification[:id].to_s,
          action: "update"
        )

        expect(captured_user_id).to eq(user[:id].to_s)
        expect(captured_msg[:type]).to eq("broadcast")
        expect(captured_msg[:action]).to eq("update")
        objects = captured_msg[:data][:objects]
        expect(objects.first).to include(objectType: "notification", id: notification[:id].to_s)
        expect(manager).not_to have_received(:broadcast_to_workspace)
      end
    end

    context "with delete payloads (audience stays inline because the object can't be reloaded)" do
      it "broadcasts a deleted marker on the workspace channel" do
        event_id = SecureRandom.uuid
        captured_msg = nil
        allow(manager).to receive(:broadcast_to_workspace) do |_ws, msg, **_|
          captured_msg = msg
        end

        invoke(
          audience: "workspace",
          audienceId: workspace[:id].to_s,
          objectType: "event",
          objectId: event_id,
          action: "delete"
        )

        expect(captured_msg[:action]).to eq("delete")
        expect(captured_msg[:data][:deleted].first).to include(objectType: "event", id: event_id)
      end

      it "broadcasts a deleted marker on the user channel" do
        notification_id = SecureRandom.uuid
        captured_msg = nil
        allow(manager).to receive(:broadcast_to_user) { |_uid, msg| captured_msg = msg }

        invoke(
          audience: "user",
          audienceId: user[:id].to_s,
          objectType: "notification",
          objectId: notification_id,
          action: "delete"
        )

        expect(captured_msg[:action]).to eq("delete")
        expect(captured_msg[:data][:deleted].first).to include(objectType: "notification", id: notification_id)
      end

      it "logs and drops a delete payload with an unknown audience kind" do
        allow(APP_LOGGER).to receive(:warn)

        invoke(
          audience: "the_void",
          audienceId: SecureRandom.uuid,
          objectType: "event",
          objectId: SecureRandom.uuid,
          action: "delete"
        )

        expect(APP_LOGGER).to have_received(:warn)
        expect(manager).not_to have_received(:broadcast_to_workspace)
        expect(manager).not_to have_received(:broadcast_to_user)
      end
    end

    it "logs and drops notifications for unknown object types" do
      allow(APP_LOGGER).to receive(:warn)

      invoke(
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
