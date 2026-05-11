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
    context "with workspace_id" do
      it "sends a pg_notify on the correct channel" do
        captured_channel = nil
        allow(DB).to receive(:run) { |lit| captured_channel = lit.args.first }

        described_class.object_changed("event", object_id, workspace_id: workspace_id)

        expect(captured_channel).to eq(Broadcaster::CHANNEL)
      end

      it "tags the payload with a workspace audience" do
        payload = capture_payload do
          described_class.object_changed("event", object_id, workspace_id: workspace_id)
        end

        expect(payload).to include(
          "audience" => "workspace",
          "audienceId" => workspace_id,
          "objectType" => "event",
          "objectId" => object_id,
          "action" => "update"
        )
      end

      it "does not raise on DB errors" do
        allow(DB).to receive(:run).and_raise(StandardError, "connection lost")

        expect do
          described_class.object_changed("event", object_id, workspace_id: workspace_id)
        end.not_to raise_error
      end
    end

    context "with user_id" do
      it "tags the payload with a user audience" do
        payload = capture_payload do
          described_class.object_changed("notification", object_id, user_id: user_id)
        end

        expect(payload).to include(
          "audience" => "user",
          "audienceId" => user_id,
          "objectType" => "notification",
          "objectId" => object_id,
          "action" => "update"
        )
      end
    end

    it "raises when neither workspace_id nor user_id is given" do
      expect do
        described_class.object_changed("event", object_id)
      end.to raise_error(ArgumentError, /audience/)
    end

    it "raises when both workspace_id and user_id are given" do
      expect do
        described_class.object_changed("event", object_id, workspace_id: workspace_id, user_id: user_id)
      end.to raise_error(ArgumentError, /audience/)
    end
  end

  describe ".object_deleted" do
    it "tags a workspace-audience deletion" do
      payload = capture_payload do
        described_class.object_deleted("event", object_id, workspace_id: workspace_id)
      end

      expect(payload).to include(
        "audience" => "workspace",
        "audienceId" => workspace_id,
        "action" => "delete"
      )
    end

    it "tags a user-audience deletion" do
      payload = capture_payload do
        described_class.object_deleted("notification", object_id, user_id: user_id)
      end

      expect(payload).to include(
        "audience" => "user",
        "audienceId" => user_id,
        "action" => "delete"
      )
    end

    it "does not raise on DB errors" do
      allow(DB).to receive(:run).and_raise(StandardError, "connection lost")

      expect do
        described_class.object_deleted("event", object_id, workspace_id: workspace_id)
      end.not_to raise_error
    end
  end
end
