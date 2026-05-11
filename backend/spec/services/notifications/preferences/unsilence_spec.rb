# frozen_string_literal: true

require "spec_helper"

RSpec.describe Notifications::Preferences::Unsilence do
  let(:user) { TestFactories.user }

  describe ".call" do
    it "clears any stored override rows for the kind so defaults apply" do
      DB[:user_notification_preferences].insert(
        user_id: user[:id], kind: "expense_added", channel: "email", enabled: false
      )
      DB[:user_notification_preferences].insert(
        user_id: user[:id], kind: "expense_added", channel: "in_app", enabled: false
      )

      result = described_class.call(user_id: user[:id], kind: "expense_added")

      expect(result.success?).to be true
      remaining = DB[:user_notification_preferences]
                  .where(user_id: user[:id], kind: "expense_added")
                  .count
      expect(remaining).to eq(0)
    end

    it "leaves other kinds' overrides alone" do
      DB[:user_notification_preferences].insert(
        user_id: user[:id], kind: "expense_added", channel: "email", enabled: false
      )
      DB[:user_notification_preferences].insert(
        user_id: user[:id], kind: "poll_closed", channel: "email", enabled: false
      )

      described_class.call(user_id: user[:id], kind: "expense_added")

      kept = DB[:user_notification_preferences]
             .where(user_id: user[:id], kind: "poll_closed")
             .all
      expect(kept.length).to eq(1)
    end

    it "leaves other users' overrides alone" do
      other = TestFactories.user
      DB[:user_notification_preferences].insert(
        user_id: other[:id], kind: "expense_added", channel: "email", enabled: false
      )

      described_class.call(user_id: user[:id], kind: "expense_added")

      kept = DB[:user_notification_preferences]
             .where(user_id: other[:id], kind: "expense_added")
             .count
      expect(kept).to eq(1)
    end

    it "is idempotent when no overrides exist" do
      result = described_class.call(user_id: user[:id], kind: "expense_added")

      expect(result.success?).to be true
    end

    it "rejects an unknown kind" do
      result = described_class.call(user_id: user[:id], kind: "no_such_kind")

      expect(result.failure?).to be true
      expect(result.failure.message).to include("kind")
    end
  end
end
