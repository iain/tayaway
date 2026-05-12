# frozen_string_literal: true

require "spec_helper"

RSpec.describe Notifications::TestPush do
  let(:user) { TestFactories.user }

  describe ".call" do
    around do |example|
      Config.with(vapid_public_key: "stub-public", vapid_private_key: "stub-private") { example.run }
    end

    before { allow(WebPush).to receive(:payload_send) }

    it "fails when push is not configured" do
      Config.with(vapid_public_key: nil, vapid_private_key: nil) do
        result = described_class.call(user_id: user[:id])

        expect(result.failure?).to be true
        expect(result.failure.message).to match(/configured/i)
      end
    end

    it "fails when the user has no subscriptions" do
      result = described_class.call(user_id: user[:id])

      expect(result.failure?).to be true
      expect(result.failure.message).to match(/no push device/i)
    end

    it "delivers to each of the user's subscriptions synchronously" do
      PushSubscription.upsert(
        user_id: user[:id],
        endpoint: "https://push.example/a",
        p256dh_key: "pa",
        auth_key: "aa"
      )
      PushSubscription.upsert(
        user_id: user[:id],
        endpoint: "https://push.example/b",
        p256dh_key: "pb",
        auth_key: "ab"
      )

      result = described_class.call(user_id: user[:id])

      expect(result.success?).to be true
      expect(result.value!).to eq(devices: 2)
      expect(WebPush).to have_received(:payload_send).twice
    end

    it "cleans up expired subscriptions and reports the issue" do
      PushSubscription.upsert(
        user_id: user[:id],
        endpoint: "https://push.example/expired",
        p256dh_key: "pe",
        auth_key: "ae"
      )
      fake_response = instance_double(Net::HTTPResponse, body: "expired", inspect: "<expired>")
      allow(WebPush).to receive(:payload_send).and_raise(
        WebPush::ExpiredSubscription.new(fake_response, "push.example")
      )

      result = described_class.call(user_id: user[:id])

      expect(result.failure?).to be true
      expect(result.failure.message).to match(/expired/i)
      remaining = DB[:push_subscriptions].where(user_id: user[:id]).count
      expect(remaining).to eq(0)
    end

    it "surfaces unexpected delivery errors" do
      PushSubscription.upsert(
        user_id: user[:id],
        endpoint: "https://push.example/broken",
        p256dh_key: "pb",
        auth_key: "ab"
      )
      allow(WebPush).to receive(:payload_send).and_raise(StandardError, "boom")

      result = described_class.call(user_id: user[:id])

      expect(result.failure?).to be true
      expect(result.failure.message).to match(/boom/i)
    end

    it "does not touch other users' subscriptions" do
      other = TestFactories.user
      PushSubscription.upsert(
        user_id: other[:id],
        endpoint: "https://push.example/other",
        p256dh_key: "po",
        auth_key: "ao"
      )

      result = described_class.call(user_id: user[:id])

      expect(result.failure?).to be true
      expect(WebPush).not_to have_received(:payload_send)
    end
  end
end
