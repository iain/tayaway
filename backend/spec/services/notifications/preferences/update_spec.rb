# frozen_string_literal: true

require "spec_helper"

RSpec.describe Notifications::Preferences::Update do
  let(:user) { TestFactories.user }

  describe ".call" do
    it "stores an override row" do
      result = described_class.call(
        user_id: user[:id],
        kind: "poll_closed",
        channel: "email",
        enabled: false
      )

      expect(result.success?).to be true
      row = DB[:user_notification_preferences]
            .where(user_id: user[:id], kind: "poll_closed", channel: "email")
            .first
      expect(row[:enabled]).to be false
    end

    it "updates an existing override row" do
      DB[:user_notification_preferences].insert(
        user_id: user[:id],
        kind: "poll_closed",
        channel: "email",
        enabled: false
      )

      described_class.call(
        user_id: user[:id],
        kind: "poll_closed",
        channel: "email",
        enabled: true
      )

      rows = DB[:user_notification_preferences]
             .where(user_id: user[:id], kind: "poll_closed", channel: "email").all
      expect(rows.length).to eq(1)
      expect(rows.first[:enabled]).to be true
    end

    it "rejects an unknown kind" do
      result = described_class.call(
        user_id: user[:id],
        kind: "no_such_kind",
        channel: "email",
        enabled: true
      )

      expect(result.failure?).to be true
      expect(result.failure.message).to include("kind")
    end

    it "rejects a channel the kind doesn't support" do
      result = described_class.call(
        user_id: user[:id],
        kind: "poll_closed",
        channel: "smoke_signal",
        enabled: true
      )

      expect(result.failure?).to be true
      expect(result.failure.message).to include("channel")
    end
  end
end
