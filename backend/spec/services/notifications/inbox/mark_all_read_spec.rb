# frozen_string_literal: true

require "spec_helper"

RSpec.describe Notifications::Inbox::MarkAllRead do
  let(:user) { TestFactories.user }
  let(:workspace) { TestFactories.workspace }

  describe ".call" do
    it "marks every unread row read and leaves already-read rows alone" do
      a = TestFactories.notification(user: user, workspace: workspace)
      b = TestFactories.notification(user: user, workspace: workspace)
      already = TestFactories.notification(user: user, workspace: workspace, read_at: Time.now - 60)
      pre_existing = DB[:notifications].where(id: already[:id]).get(:read_at)

      result = described_class.call(user_id: user[:id])

      expect(result.success?).to be true
      expect(DB[:notifications].where(user_id: user[:id], read_at: nil).count).to eq(0)
      expect(DB[:notifications].where(id: already[:id]).get(:read_at)).to eq(pre_existing)
      expect([a[:id], b[:id]]).to all(satisfy { |id| !DB[:notifications].where(id: id).get(:read_at).nil? })
    end

    it "broadcasts each row that was actually flipped" do
      a = TestFactories.notification(user: user, workspace: workspace)
      b = TestFactories.notification(user: user, workspace: workspace)
      TestFactories.notification(user: user, workspace: workspace, read_at: Time.now - 60)
      allow(Broadcaster).to receive(:object_changed)

      described_class.call(user_id: user[:id])

      expect(Broadcaster).to have_received(:object_changed).with("notification", a[:id])
      expect(Broadcaster).to have_received(:object_changed).with("notification", b[:id])
      expect(Broadcaster).to have_received(:object_changed).twice
    end

    it "doesn't broadcast when nothing was unread" do
      TestFactories.notification(user: user, workspace: workspace, read_at: Time.now - 60)
      allow(Broadcaster).to receive(:object_changed)

      described_class.call(user_id: user[:id])

      expect(Broadcaster).not_to have_received(:object_changed)
    end

    it "doesn't touch another user's notifications" do
      other = TestFactories.user
      other_row = TestFactories.notification(user: other, workspace: workspace)

      described_class.call(user_id: user[:id])

      expect(DB[:notifications].where(id: other_row[:id]).get(:read_at)).to be_nil
    end
  end
end
