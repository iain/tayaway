# frozen_string_literal: true

require "spec_helper"

RSpec.describe Broadcaster do
  let(:workspace_id) { SecureRandom.uuid }
  let(:user_id) { SecureRandom.uuid }
  let(:object_id) { SecureRandom.uuid }

  def capture_payload
    captured = nil
    allow(DB).to receive(:run) { |lit| captured = JSON.parse(lit.args.last) }
    yield
    captured
  end

  describe ".object_changed" do
    it "sends a pg_notify on the correct channel" do
      captured_channel = nil
      allow(DB).to receive(:run) { |lit| captured_channel = lit.args.first }

      described_class.object_changed("event", object_id)

      expect(captured_channel).to eq(Broadcaster::CHANNEL)
    end

    it "carries only the type and id — the Listener derives the topic set from the loaded object" do
      payload = capture_payload do
        described_class.object_changed("event", object_id)
      end

      expect(payload).to eq(
        "objectType" => "event",
        "objectId" => object_id,
        "action" => "update"
      )
    end

    it "does not raise on DB errors" do
      allow(DB).to receive(:run).and_raise(StandardError, "connection lost")

      expect do
        described_class.object_changed("event", object_id)
      end.not_to raise_error
    end
  end

  describe ".object_deleted" do
    it "carries the topic list inline as wire strings because the object can't be reloaded after delete" do
      payload = capture_payload do
        described_class.object_deleted("event", object_id, topics: [Topic.workspace(workspace_id)])
      end

      expect(payload).to include(
        "objectType" => "event",
        "objectId" => object_id,
        "action" => "delete",
        "topics" => ["workspace:#{workspace_id}"]
      )
    end

    it "accepts a user topic the same way" do
      payload = capture_payload do
        described_class.object_deleted("notification", object_id, topics: [Topic.user(user_id)])
      end

      expect(payload).to include(
        "objectType" => "notification",
        "objectId" => object_id,
        "action" => "delete",
        "topics" => ["user:#{user_id}"]
      )
    end

    it "accepts multiple topics on a single delete" do
      payload = capture_payload do
        described_class.object_deleted(
          "member", object_id,
          topics: [Topic.workspace(workspace_id), Topic.user(user_id)]
        )
      end

      expect(payload["topics"]).to contain_exactly(
        "workspace:#{workspace_id}",
        "user:#{user_id}"
      )
    end

    it "raises when topics is empty" do
      expect do
        described_class.object_deleted("event", object_id, topics: [])
      end.to raise_error(ArgumentError, /topic/)
    end

    it "rejects raw strings — producers must pass Topic instances" do
      expect do
        described_class.object_deleted("event", object_id, topics: ["workspace:#{workspace_id}"])
      end.to raise_error(ArgumentError, /Topic instances/)
    end

    it "does not raise on DB errors" do
      allow(DB).to receive(:run).and_raise(StandardError, "connection lost")

      expect do
        described_class.object_deleted("event", object_id, topics: [Topic.workspace(workspace_id)])
      end.not_to raise_error
    end
  end
end
