# frozen_string_literal: true

require "spec_helper"

RSpec.describe AdminSession do
  describe ".find_valid" do
    it "returns the session matching the plaintext token" do
      user = TestFactories.user
      row = TestFactories.admin_session(user: user)

      session = described_class.find_valid(row[:token])

      expect(session).not_to be_nil
      expect(session.user_id.to_s).to eq(user[:id])
    end

    it "returns nil for an expired session" do
      row = TestFactories.admin_session(expires_at: Time.now - 60)

      expect(described_class.find_valid(row[:token])).to be_nil
    end

    it "returns nil for an unknown token" do
      expect(described_class.find_valid("nonexistent")).to be_nil
    end
  end
end
