# frozen_string_literal: true

require "spec_helper"
require "async"

RSpec.describe Websocket::Listener do
  # Reset class-level state between examples so tests are isolated.
  after do
    described_class.instance_variable_set(:@task, nil)
  end

  describe ".running?" do
    it "returns false before start is called" do
      expect(described_class.running?).to be(false)
    end

    it "returns true while a non-finished task is registered" do
      task_double = instance_double(Async::Task, finished?: false)
      described_class.instance_variable_set(:@task, task_double)

      expect(described_class.running?).to be(true)
    end

    it "returns false once the task has finished" do
      task_double = instance_double(Async::Task, finished?: true)
      described_class.instance_variable_set(:@task, task_double)

      expect(described_class.running?).to be(false)
    end
  end

  describe ".start" do
    it "raises when called outside an Async reactor" do
      expect { described_class.start }.to raise_error(/Async reactor/)
    end

    it "spawns a task on the current reactor and is idempotent" do
      allow(APP_LOGGER).to receive(:info)
      # Stub the run loop so the spawned task exits immediately and doesn't
      # hold the reactor open by polling Sequel.
      allow(described_class).to receive(:run_loop)

      Sync do
        described_class.start
        first = described_class.instance_variable_get(:@task)
        described_class.start
        second = described_class.instance_variable_get(:@task)

        expect(first).to be_a(Async::Task)
        expect(second).to equal(first)
      end
    end
  end

  describe ".stop" do
    it "is a no-op when not running" do
      allow(APP_LOGGER).to receive(:info)

      expect { described_class.stop }.not_to raise_error
      expect(described_class.running?).to be(false)
    end

    it "stops the task and clears state" do
      allow(APP_LOGGER).to receive(:info)
      allow(described_class).to receive(:run_loop)

      Sync do
        described_class.start
        described_class.stop

        expect(described_class.running?).to be(false)
        expect(described_class.instance_variable_get(:@task)).to be_nil
      end
    end

    it "stops the spawned task so Async::Stop unwinds through the parked listen call" do
      allow(APP_LOGGER).to receive(:info)
      task_double = instance_double(Async::Task, stop: nil)
      described_class.instance_variable_set(:@task, task_double)

      described_class.stop

      expect(task_double).to have_received(:stop)
      expect(described_class.instance_variable_get(:@task)).to be_nil
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
end
