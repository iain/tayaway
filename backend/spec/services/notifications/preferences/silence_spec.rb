# frozen_string_literal: true

require "spec_helper"

RSpec.describe Notifications::Preferences::Silence do
  let(:user) { TestFactories.user }

  describe ".call" do
    it "writes off rows for every configurable channel of the kind" do
      result = described_class.call(user_id: user[:id], kind: "expense_added")

      expect(result.success?).to be true
      rows = DB[:user_notification_preferences]
             .where(user_id: user[:id], kind: "expense_added")
             .all
      channels = rows.map { |r| [r[:channel], r[:enabled]] }
      expect(channels).to contain_exactly(
        ["email", false],
        ["in_app", false],
        ["push", false]
      )
    end

    it "skips forced channels rather than rejecting the whole call" do
      # passkey_changed forces email; in_app and push are configurable.
      # Silencing should write off rows only for the configurable channels;
      # email stays untouched because the dispatcher would override a stored
      # off anyway.
      result = described_class.call(user_id: user[:id], kind: "passkey_changed")

      expect(result.success?).to be true
      rows = DB[:user_notification_preferences]
             .where(user_id: user[:id], kind: "passkey_changed")
             .all
      channels = rows.map { |r| [r[:channel], r[:enabled]] }
      expect(channels).to contain_exactly(
        ["in_app", false],
        ["push", false]
      )
    end

    it "is idempotent" do
      described_class.call(user_id: user[:id], kind: "expense_added")
      described_class.call(user_id: user[:id], kind: "expense_added")

      rows = DB[:user_notification_preferences]
             .where(user_id: user[:id], kind: "expense_added")
             .all
      expect(rows.length).to eq(3)
    end

    it "does not touch other users' preferences" do
      other = TestFactories.user
      DB[:user_notification_preferences].insert(
        user_id: other[:id],
        kind: "expense_added",
        channel: "email",
        enabled: true
      )

      described_class.call(user_id: user[:id], kind: "expense_added")

      other_row = DB[:user_notification_preferences]
                  .where(user_id: other[:id], kind: "expense_added", channel: "email")
                  .first
      expect(other_row[:enabled]).to be true
    end

    it "rejects an unknown kind" do
      result = described_class.call(user_id: user[:id], kind: "no_such_kind")

      expect(result.failure?).to be true
      expect(result.failure.message).to include("kind")
    end
  end
end
