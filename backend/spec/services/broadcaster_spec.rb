# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Broadcaster do
  let(:workspace_id) { SecureRandom.uuid }
  let(:object_id) { SecureRandom.uuid }

  describe ".object_changed" do
    it "sends a pg_notify with update action" do
      notifications = []
      allow(DB).to receive(:run) do |lit|
        notifications << lit.to_s
      end

      described_class.object_changed("event", object_id, workspace_id: workspace_id)

      expect(notifications.length).to eq(1)
    end

    it "does not raise on DB errors" do
      allow(DB).to receive(:run).and_raise(StandardError, "connection lost")

      expect do
        described_class.object_changed("event", object_id, workspace_id: workspace_id)
      end.not_to raise_error
    end
  end

  describe ".object_deleted" do
    it "sends a pg_notify with delete action" do
      notifications = []
      allow(DB).to receive(:run) do |lit|
        notifications << lit.to_s
      end

      described_class.object_deleted("event", object_id, workspace_id: workspace_id)

      expect(notifications.length).to eq(1)
    end

    it "does not raise on DB errors" do
      allow(DB).to receive(:run).and_raise(StandardError, "connection lost")

      expect do
        described_class.object_deleted("event", object_id, workspace_id: workspace_id)
      end.not_to raise_error
    end
  end
end
