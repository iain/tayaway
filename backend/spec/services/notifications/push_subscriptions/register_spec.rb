# frozen_string_literal: true

require "spec_helper"

RSpec.describe Notifications::PushSubscriptions::Register do
  let(:user) { TestFactories.user }

  describe ".call" do
    it "stores a new subscription row" do
      result = described_class.call(
        user_id: user[:id],
        endpoint: "https://push.example.com/abc",
        p256dh_key: "p256dh-test",
        auth_key: "auth-test",
        user_agent: "Mozilla/5.0"
      )

      expect(result.success?).to be true
      row = DB[:push_subscriptions].where(user_id: user[:id]).first
      expect(row[:endpoint]).to eq("https://push.example.com/abc")
      expect(row[:user_agent]).to eq("Mozilla/5.0")
    end

    it "returns the VAPID public key so the page can confirm it matches" do
      stub_const("ENV", ENV.to_h.merge("VAPID_PUBLIC_KEY" => "k-public"))

      result = described_class.call(
        user_id: user[:id],
        endpoint: "https://push.example.com/abc",
        p256dh_key: "p", auth_key: "a"
      )

      expect(result.value!).to include(ok: true, vapidPublicKey: "k-public")
    end

    it "rejects an empty endpoint" do
      result = described_class.call(
        user_id: user[:id],
        endpoint: "",
        p256dh_key: "p", auth_key: "a"
      )

      expect(result.failure?).to be true
      expect(result.failure.message).to include("endpoint")
    end

    it "rejects a nil endpoint" do
      result = described_class.call(
        user_id: user[:id],
        endpoint: nil,
        p256dh_key: "p", auth_key: "a"
      )

      expect(result.failure?).to be true
    end
  end
end
