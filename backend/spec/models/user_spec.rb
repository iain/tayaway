# frozen_string_literal: true

require "spec_helper"

RSpec.describe User do
  describe "#to_api_hash" do
    it "does not include iban field" do
      user_data = TestFactories.user(name: "Test")
      DB[:users].where(id: user_data[:id]).update(iban: Encryption.encrypt("NL91ABNA0417164300", user_id: user_data[:id]))

      user = described_class.find(user_data[:id])
      hash = user.to_api_hash

      expect(hash).not_to have_key(:iban)
      expect(hash[:objectType]).to eq("user")
      expect(hash[:name]).to eq("Test")
    end
  end
end
