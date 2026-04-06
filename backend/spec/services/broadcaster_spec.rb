# frozen_string_literal: true

require "spec_helper"

RSpec.describe Broadcaster do
  let(:workspace_id) { SecureRandom.uuid }
  let(:object_id) { SecureRandom.uuid }

  describe ".object_changed" do
    it "sends a pg_notify on the correct channel" do
      captured_channel = nil
      allow(DB).to receive(:run) { |lit| captured_channel = lit.args.first }

      described_class.object_changed("event", object_id, workspace_id: workspace_id)

      expect(captured_channel).to eq(Broadcaster::CHANNEL)
    end

    it "includes workspaceId in the payload" do
      captured_payload = nil
      allow(DB).to receive(:run) { |lit| captured_payload = JSON.parse(lit.args.last) }

      described_class.object_changed("event", object_id, workspace_id: workspace_id)

      expect(captured_payload["workspaceId"]).to eq(workspace_id)
    end

    it "includes objectType in the payload" do
      captured_payload = nil
      allow(DB).to receive(:run) { |lit| captured_payload = JSON.parse(lit.args.last) }

      described_class.object_changed("event", object_id, workspace_id: workspace_id)

      expect(captured_payload["objectType"]).to eq("event")
    end

    it "includes objectId in the payload" do
      captured_payload = nil
      allow(DB).to receive(:run) { |lit| captured_payload = JSON.parse(lit.args.last) }

      described_class.object_changed("event", object_id, workspace_id: workspace_id)

      expect(captured_payload["objectId"]).to eq(object_id)
    end

    it "sets action to update" do
      captured_payload = nil
      allow(DB).to receive(:run) { |lit| captured_payload = JSON.parse(lit.args.last) }

      described_class.object_changed("event", object_id, workspace_id: workspace_id)

      expect(captured_payload["action"]).to eq("update")
    end

    it "does not raise on DB errors" do
      allow(DB).to receive(:run).and_raise(StandardError, "connection lost")

      expect do
        described_class.object_changed("event", object_id, workspace_id: workspace_id)
      end.not_to raise_error
    end
  end

  describe ".object_deleted" do
    it "sends a pg_notify on the correct channel" do
      captured_channel = nil
      allow(DB).to receive(:run) { |lit| captured_channel = lit.args.first }

      described_class.object_deleted("event", object_id, workspace_id: workspace_id)

      expect(captured_channel).to eq(Broadcaster::CHANNEL)
    end

    it "includes workspaceId in the payload" do
      captured_payload = nil
      allow(DB).to receive(:run) { |lit| captured_payload = JSON.parse(lit.args.last) }

      described_class.object_deleted("event", object_id, workspace_id: workspace_id)

      expect(captured_payload["workspaceId"]).to eq(workspace_id)
    end

    it "includes objectType in the payload" do
      captured_payload = nil
      allow(DB).to receive(:run) { |lit| captured_payload = JSON.parse(lit.args.last) }

      described_class.object_deleted("vote", object_id, workspace_id: workspace_id)

      expect(captured_payload["objectType"]).to eq("vote")
    end

    it "includes objectId in the payload" do
      captured_payload = nil
      allow(DB).to receive(:run) { |lit| captured_payload = JSON.parse(lit.args.last) }

      described_class.object_deleted("event", object_id, workspace_id: workspace_id)

      expect(captured_payload["objectId"]).to eq(object_id)
    end

    it "sets action to delete" do
      captured_payload = nil
      allow(DB).to receive(:run) { |lit| captured_payload = JSON.parse(lit.args.last) }

      described_class.object_deleted("event", object_id, workspace_id: workspace_id)

      expect(captured_payload["action"]).to eq("delete")
    end

    it "does not raise on DB errors" do
      allow(DB).to receive(:run).and_raise(StandardError, "connection lost")

      expect do
        described_class.object_deleted("event", object_id, workspace_id: workspace_id)
      end.not_to raise_error
    end
  end
end
