# frozen_string_literal: true

require "spec_helper"

RSpec.describe Auth::Passkeys::OnChanged do
  describe ".call" do
    let(:user) { TestFactories.user }

    it "writes a notification row when a passkey is added" do
      described_class.call(user_id: user[:id], passkey_name: "MacBook", action: "added")

      row = DB[:notifications].where(user_id: user[:id], kind: "passkey_changed").first
      expect(row).not_to be_nil
      expect(row[:data]["title"]).to include("added")
    end

    it "writes a notification row when a passkey is removed" do
      described_class.call(user_id: user[:id], passkey_name: "MacBook", action: "removed")

      row = DB[:notifications].where(user_id: user[:id], kind: "passkey_changed").first
      expect(row[:data]["title"]).to include("removed")
    end

    it "is silent when the user has vanished" do
      ghost = SecureRandom.uuid

      described_class.call(user_id: ghost, passkey_name: "X", action: "added")

      expect(DB[:notifications].count).to eq(0)
    end
  end
end
