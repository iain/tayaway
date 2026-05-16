# frozen_string_literal: true

require "spec_helper"

RSpec.describe Notifications::Inbox::MarkRead do
  let(:user) { TestFactories.user }
  let(:workspace) { TestFactories.workspace }

  describe ".call" do
    it "marks an unread notification read" do
      row = TestFactories.notification(user: user, workspace: workspace)

      result = described_class.call(id: row[:id], user_id: user[:id])

      expect(result.success?).to be true
      expect(DB[:notifications].where(id: row[:id]).get(:read_at)).not_to be_nil
    end

    it "broadcasts the change so other devices update" do
      row = TestFactories.notification(user: user, workspace: workspace)
      allow(Broadcaster).to receive(:object_changed)

      described_class.call(id: row[:id], user_id: user[:id])

      expect(Broadcaster).to have_received(:object_changed)
        .with("notification", row[:id])
    end

    it "is a no-op for an already-read row" do
      row = TestFactories.notification(user: user, workspace: workspace, read_at: Time.now - 60)
      allow(Broadcaster).to receive(:object_changed)

      result = described_class.call(id: row[:id], user_id: user[:id])

      expect(result.success?).to be true
      expect(Broadcaster).not_to have_received(:object_changed)
    end

    it "doesn't mark another user's notification" do
      other = TestFactories.user
      row = TestFactories.notification(user: other, workspace: workspace)
      allow(Broadcaster).to receive(:object_changed)

      described_class.call(id: row[:id], user_id: user[:id])

      expect(DB[:notifications].where(id: row[:id]).get(:read_at)).to be_nil
      expect(Broadcaster).not_to have_received(:object_changed)
    end
  end
end
