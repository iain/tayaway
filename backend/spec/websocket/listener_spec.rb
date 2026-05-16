# frozen_string_literal: true

require "spec_helper"

RSpec.describe Websocket::Listener do
  describe ".handle_notification" do
    let(:workspace) { TestFactories.workspace }
    let(:user) { TestFactories.user }
    let(:manager) do
      instance_double(
        Websocket::ConnectionManager,
        broadcast: nil,
        connections_for_user: [],
        subscribed?: true,
        subscribe: nil,
        set_membership: nil,
        send_to_connections: nil
      )
    end

    def invoke(payload)
      described_class.handle_notification(payload.to_json, manager)
    end

    def captured_topics
      received = []
      allow(manager).to receive(:broadcast) do |topic, _msg, **_|
        received << topic
      end
      yield
      received
    end

    context "with update payloads (no topic inline — Listener derives from the loaded object)" do
      it "threads a PolicyContext built from the pool into the workspace broadcast" do
        event_row = TestFactories.event(workspace: workspace, user: user)

        captured = nil
        allow(manager).to receive(:broadcast) do |_topic, _msg, policy_context: nil|
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

      it "addresses event broadcasts to the workspace topic" do
        event_row = TestFactories.event(workspace: workspace, user: user)

        topics = captured_topics do
          invoke(
            objectType: "event",
            objectId: event_row[:id].to_s,
            action: "update"
          )
        end

        expect(topics).to eq([Topic.workspace(workspace[:id])])
      end

      it "drops the update when the object is gone — the corresponding delete NOTIFY handles cleanup" do
        ghost_id = SecureRandom.uuid

        invoke(
          objectType: "event",
          objectId: ghost_id,
          action: "update"
        )

        expect(manager).not_to have_received(:broadcast)
      end

      it "ships a member update to the workspace topic only — the user gets it because they're auto-subscribed" do
        membership_row = TestFactories.workspace_membership(workspace: workspace, user: user, role: "member")
        # Subscribed to that workspace already — the auto-subscribed path.
        allow(manager).to receive(:subscribed?).and_return(true)

        captured = []
        allow(manager).to receive(:broadcast) do |topic, msg, **_|
          captured << [topic, msg]
        end

        invoke(
          objectType: "member",
          objectId: membership_row[:id],
          action: "update"
        )

        expect(captured.size).to eq(1)
        topic, msg = captured.first
        expect(topic).to eq(Topic.workspace(workspace[:id]))
        expect(msg.dig(:data, :objects, 0)).to include(
          objectType: "member",
          id: membership_row[:id]
        )
      end

      it "bootstraps a freshly-added member: subscribes their connections + ships a WorkspaceSync before the workspace broadcast" do
        # This is the new-workspace bootstrap path: the user is freshly
        # added to a workspace, their existing connections are not yet
        # subscribed to its topic. The Listener subscribes them, loads
        # the membership for permission attachment, and direct-sends a
        # WorkspaceSync so the pool gets the workspace row + initial data.
        membership_row = TestFactories.workspace_membership(workspace: workspace, user: user, role: "member")
        conn_id = SecureRandom.uuid

        allow(manager).to receive(:connections_for_user).with(user[:id].to_s).and_return([conn_id])
        allow(manager).to receive(:subscribed?).with(conn_id, Topic.workspace(workspace[:id])).and_return(false)

        invoke(
          objectType: "member",
          objectId: membership_row[:id],
          action: "update"
        )

        expect(manager).to have_received(:set_membership)
          .with(conn_id, workspace[:id].to_s, kind_of(WorkspaceMembership))
        expect(manager).to have_received(:subscribe).with(conn_id, Topic.workspace(workspace[:id]))
        expect(manager).to have_received(:send_to_connections) do |conn_ids, msg|
          expect(conn_ids).to eq([conn_id])
          expect(msg[:type]).to eq("sync")
          expect(msg[:data][:syncType]).to eq("full").or eq("partial")
        end
      end

      it "broadcasts a notification to its user topic" do
        notification = TestFactories.notification(user: user, workspace: workspace)

        topics = captured_topics do
          invoke(
            objectType: "notification",
            objectId: notification[:id].to_s,
            action: "update"
          )
        end

        expect(topics).to eq([Topic.user(user[:id])])
      end
    end

    context "with delete payloads (topics stay inline because the object can't be reloaded)" do
      it "broadcasts a deleted marker on each topic carried in the payload" do
        event_id = SecureRandom.uuid

        captured = []
        allow(manager).to receive(:broadcast) do |topic, msg, **_|
          captured << [topic, msg]
        end

        invoke(
          topics: ["workspace:#{workspace[:id]}"],
          objectType: "event",
          objectId: event_id,
          action: "delete"
        )

        expect(captured.size).to eq(1)
        topic, msg = captured.first
        expect(topic).to eq(Topic.workspace(workspace[:id]))
        expect(msg[:action]).to eq("delete")
        expect(msg[:data][:deleted].first).to include(objectType: "event", id: event_id)
      end

      it "broadcasts a deleted marker on the user topic" do
        notification_id = SecureRandom.uuid

        captured = []
        allow(manager).to receive(:broadcast) do |topic, msg, **_|
          captured << [topic, msg]
        end

        invoke(
          topics: ["user:#{user[:id]}"],
          objectType: "notification",
          objectId: notification_id,
          action: "delete"
        )

        expect(captured.size).to eq(1)
        topic, msg = captured.first
        expect(topic).to eq(Topic.user(user[:id]))
        expect(msg[:action]).to eq("delete")
        expect(msg[:data][:deleted].first).to include(objectType: "notification", id: notification_id)
      end

      it "logs and drops a delete payload with an unknown topic namespace" do
        allow(APP_LOGGER).to receive(:warn)

        invoke(
          topics: ["the_void:#{SecureRandom.uuid}"],
          objectType: "event",
          objectId: SecureRandom.uuid,
          action: "delete"
        )

        expect(APP_LOGGER).to have_received(:warn)
        expect(manager).not_to have_received(:broadcast)
      end

      it "logs and drops a delete payload with no topics" do
        allow(APP_LOGGER).to receive(:warn)

        invoke(
          objectType: "event",
          objectId: SecureRandom.uuid,
          action: "delete"
        )

        expect(manager).not_to have_received(:broadcast)
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
      expect(manager).not_to have_received(:broadcast)
    end

    it "logs and drops malformed JSON without raising" do
      allow(APP_LOGGER).to receive(:error)

      expect { described_class.handle_notification("not-json", manager) }.not_to raise_error
      expect(APP_LOGGER).to have_received(:error)
    end
  end
end
