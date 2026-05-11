# frozen_string_literal: true

require "spec_helper"

RSpec.describe Notifications::PushSubscriptions::Unregister do
  let(:user) { TestFactories.user }

  describe ".call" do
    it "deletes the user's subscription with the given endpoint" do
      PushSubscription.upsert(
        user_id: user[:id],
        endpoint: "https://push.example.com/abc",
        p256dh_key: "p", auth_key: "a"
      )

      result = described_class.call(user_id: user[:id], endpoint: "https://push.example.com/abc")

      expect(result.success?).to be true
      expect(DB[:push_subscriptions].where(user_id: user[:id]).count).to eq(0)
    end

    it "is a no-op when the endpoint isn't registered" do
      result = described_class.call(user_id: user[:id], endpoint: "https://push.example.com/missing")

      expect(result.success?).to be true
    end

    it "doesn't touch another user's subscription with the same endpoint" do
      other = TestFactories.user
      PushSubscription.upsert(
        user_id: other[:id],
        endpoint: "https://push.example.com/abc",
        p256dh_key: "p", auth_key: "a"
      )

      described_class.call(user_id: user[:id], endpoint: "https://push.example.com/abc")

      expect(DB[:push_subscriptions].where(user_id: other[:id]).count).to eq(1)
    end
  end
end
