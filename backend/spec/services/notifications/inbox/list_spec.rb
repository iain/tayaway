# frozen_string_literal: true

require "spec_helper"

RSpec.describe Notifications::Inbox::List do
  let(:user) { TestFactories.user }
  let(:workspace) { TestFactories.workspace }

  describe ".call" do
    it "returns the user's notifications as a pool envelope, newest first" do
      old = TestFactories.notification(user: user, workspace: workspace)
      newer = TestFactories.notification(user: user, workspace: workspace)
      DB[:notifications].where(id: old[:id]).update(created_at: Time.now - 60)

      result = described_class.call(user_id: user[:id])

      expect(result.success?).to be true
      objects = result.value![:objects]
      expect(objects.map { |o| o[:objectType] }).to all(eq("notification"))
      expect(objects.map { |o| o[:id] }).to eq([newer[:id], old[:id]])
    end

    it "doesn't leak another user's notifications" do
      other = TestFactories.user
      TestFactories.notification(user: other, workspace: workspace)

      result = described_class.call(user_id: user[:id])

      expect(result.value![:objects]).to be_empty
    end
  end
end
