# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Auth::Passkeys::Delete do
  let(:user) { TestFactories.user }

  it "deletes a passkey belonging to the user" do
    passkey = TestFactories.passkey_credential(user: user, name: "My Key")

    result = described_class.call(user_id: user[:id], passkey_id: passkey[:id])

    expect(result.success?).to be true
    expect(DB[:passkey_credentials].where(id: passkey[:id]).count).to eq(0)
  end

  it "returns failure when passkey does not exist" do
    result = described_class.call(user_id: user[:id], passkey_id: SecureRandom.uuid)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Passkey not found")
  end

  it "returns failure when passkey belongs to another user" do
    other_user = TestFactories.user
    passkey = TestFactories.passkey_credential(user: other_user)

    result = described_class.call(user_id: user[:id], passkey_id: passkey[:id])

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Not authorized")
  end
end
