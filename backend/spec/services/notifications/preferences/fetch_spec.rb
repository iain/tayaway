# frozen_string_literal: true

require "spec_helper"

RSpec.describe Notifications::Preferences::Fetch do
  let(:user) { TestFactories.user }

  describe ".call" do
    it "returns every registered kind with its default channels enabled" do
      result = described_class.call(user_id: user[:id])

      expect(result.success?).to be true
      kinds = result.value![:kinds]
      keys = kinds.map { |k| k[:key] }
      expect(keys).to include("workspace_invite", "poll_closed", "settlement_created")
      poll_closed = kinds.find { |k| k[:key] == "poll_closed" }
      expect(poll_closed[:channels].find { |c| c[:channel] == "email" }).to include(enabled: true)
    end

    it "applies a stored override on top of the defaults" do
      DB[:user_notification_preferences].insert(
        user_id: user[:id],
        kind: "poll_closed",
        channel: "email",
        enabled: false
      )

      result = described_class.call(user_id: user[:id])

      poll_closed = result.value![:kinds].find { |k| k[:key] == "poll_closed" }
      expect(poll_closed[:channels].first).to include(channel: "email", enabled: false)
    end

    it "ignores another user's overrides" do
      other = TestFactories.user
      DB[:user_notification_preferences].insert(
        user_id: other[:id],
        kind: "poll_closed",
        channel: "email",
        enabled: false
      )

      result = described_class.call(user_id: user[:id])

      poll_closed = result.value![:kinds].find { |k| k[:key] == "poll_closed" }
      expect(poll_closed[:channels].first).to include(enabled: true)
    end
  end
end
