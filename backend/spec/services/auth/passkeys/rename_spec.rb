# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Auth::Passkeys::Rename do
  let(:user) { TestFactories.user }

  it "renames a passkey" do
    passkey = TestFactories.passkey_credential(user: user, name: "Old")

    result = described_class.call(user_id: user[:id], passkey_id: passkey[:id], name: "New")

    expect(result.success?).to be true
    expect(result.value![:passkey][:name]).to eq("New")
    expect(DB[:passkey_credentials].where(id: passkey[:id]).first[:name]).to eq("New")
  end

  it "strips whitespace from name" do
    passkey = TestFactories.passkey_credential(user: user)

    result = described_class.call(user_id: user[:id], passkey_id: passkey[:id], name: "  Trimmed  ")

    expect(result.success?).to be true
    expect(result.value![:passkey][:name]).to eq("Trimmed")
  end

  it "returns failure for blank name" do
    passkey = TestFactories.passkey_credential(user: user)

    result = described_class.call(user_id: user[:id], passkey_id: passkey[:id], name: "  ")

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Name is required")
  end

  it "returns failure for nil name" do
    passkey = TestFactories.passkey_credential(user: user)

    result = described_class.call(user_id: user[:id], passkey_id: passkey[:id], name: nil)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Name is required")
  end

  it "returns failure for name exceeding max length" do
    passkey = TestFactories.passkey_credential(user: user)

    result = described_class.call(user_id: user[:id], passkey_id: passkey[:id], name: "x" * 101)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Name must be 100 characters or fewer")
  end

  it "returns failure for non-existent passkey" do
    result = described_class.call(user_id: user[:id], passkey_id: SecureRandom.uuid, name: "Test")

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Passkey not found")
  end

  it "returns failure for another user's passkey" do
    other = TestFactories.user
    passkey = TestFactories.passkey_credential(user: other)

    result = described_class.call(user_id: user[:id], passkey_id: passkey[:id], name: "Hijack")

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Passkey not found")
  end
end
