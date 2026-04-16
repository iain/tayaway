# frozen_string_literal: true

require "spec_helper"

RSpec.describe Websocket::Listener do
  # Reset class-level state between examples so tests are isolated.
  after do
    described_class.instance_variable_set(:@_running_flag, nil)
    described_class.instance_variable_set(:@listen_db, nil)
    described_class.instance_variable_set(:@thread, nil)
  end

  describe ".running?" do
    it "returns false before start is called" do
      expect(described_class.running?).to be(false)
    end

    it "returns true after start is called" do
      allow(Thread).to receive(:new).and_return(double(abort_on_exception: true, "abort_on_exception=": true))
      allow(APP_LOGGER).to receive(:info)

      described_class.start

      expect(described_class.running?).to be(true)
    end
  end

  describe ".start" do
    it "is idempotent — calling twice does not spawn a second thread" do
      thread_double = double(abort_on_exception: true, "abort_on_exception=": true)
      allow(Thread).to receive(:new).once.and_return(thread_double)
      allow(APP_LOGGER).to receive(:info)

      described_class.start
      described_class.start

      expect(Thread).to have_received(:new).once
    end
  end

  describe ".stop" do
    it "is a no-op when not running" do
      allow(APP_LOGGER).to receive(:info)

      expect { described_class.stop }.not_to raise_error
      expect(described_class.running?).to be(false)
    end

    it "sets running? to false after stopping" do
      thread_double = double("abort_on_exception=": true)
      allow(thread_double).to receive(:join)
      allow(Thread).to receive(:new).and_return(thread_double)
      allow(APP_LOGGER).to receive(:info)

      described_class.start
      described_class.stop

      expect(described_class.running?).to be(false)
    end
  end

  describe ".handle_notification" do
    let(:workspace) { TestFactories.workspace }
    let(:user) { TestFactories.user }
    let(:manager) { Websocket::ConnectionManager.instance }

    def invoke(payload)
      described_class.send(:handle_notification, payload.to_json)
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
      allow(manager).to receive(:broadcast_to_workspace)

      invoke(
        workspaceId: workspace[:id].to_s,
        objectType: "not_a_real_type",
        objectId: SecureRandom.uuid,
        action: "update"
      )

      expect(APP_LOGGER).to have_received(:warn)
      expect(manager).not_to have_received(:broadcast_to_workspace)
    end
  end

  describe "thread-safety of the running flag" do
    it "uses a Concurrent::AtomicBoolean for the running flag" do
      flag = described_class.send(:running_flag)

      expect(flag).to be_a(Concurrent::AtomicBoolean)
    end

    it "reflects make_true atomically" do
      flag = described_class.send(:running_flag)
      flag.make_true

      expect(described_class.running?).to be(true)
    end

    it "reflects make_false atomically" do
      flag = described_class.send(:running_flag)
      flag.make_true
      flag.make_false

      expect(described_class.running?).to be(false)
    end
  end
end
