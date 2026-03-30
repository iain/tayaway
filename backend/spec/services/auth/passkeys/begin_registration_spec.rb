# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Auth::Passkeys::BeginRegistration do
  let(:user) { TestFactories.user }

  it "returns WebAuthn creation options" do
    result = described_class.call(user_id: user[:id])

    expect(result.success?).to be true
    value = result.value!
    expect(value[:options]).to include(:challenge, :rp, :user, :pubKeyCredParams)
    expect(value[:options][:rp][:name]).to eq("Tayaway")
    expect(value[:options][:user][:name]).to eq(user[:email])
    expect(value[:challengeToken]).to be_a(String)
  end

  it "includes existing credentials in excludeCredentials" do
    TestFactories.passkey_credential(user: user, external_id: "existing-cred-id")

    result = described_class.call(user_id: user[:id])

    expect(result.success?).to be true
    exclude = result.value![:options][:excludeCredentials]
    expect(exclude).to be_an(Array)
    expect(exclude.length).to eq(1)
    expect(exclude.first[:id]).to eq("existing-cred-id")
  end

  it "returns failure for non-existent user" do
    result = described_class.call(user_id: SecureRandom.uuid)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("User not found")
  end
end
