# typed: false
# frozen_string_literal: true

require "spec_helper"
require "webauthn/fake_client"

RSpec.describe Auth::Passkeys::CompleteRegistration do
  let(:user) { TestFactories.user }
  let(:fake_client) { WebAuthn::FakeClient.new("http://localhost:5173") }

  def begin_and_create
    begin_result = Auth::Passkeys::BeginRegistration.call(user_id: user[:id])
    options = begin_result.value!
    credential = fake_client.create(challenge: options[:options][:challenge])
    [options[:challengeToken], credential]
  end

  it "registers a passkey and returns its details" do
    challenge_token, credential = begin_and_create

    result = described_class.call(
      user_id: user[:id],
      challenge_token: challenge_token,
      credential: credential,
      name: "My YubiKey"
    )

    expect(result.success?).to be true
    passkey = result.value![:passkey]
    expect(passkey[:id]).to be_a(String)
    expect(passkey[:name]).to eq("My YubiKey")
    expect(passkey[:createdAt]).to be_a(String)

    expect(DB[:passkey_credentials].where(user_id: user[:id]).count).to eq(1)
  end

  it "stores the credential in the database" do
    challenge_token, credential = begin_and_create

    described_class.call(
      user_id: user[:id],
      challenge_token: challenge_token,
      credential: credential
    )

    row = DB[:passkey_credentials].where(user_id: user[:id]).first
    expect(row[:external_id]).to eq(credential["id"])
    expect(row[:public_key]).to be_a(String)
    expect(row[:sign_count]).to eq(0)
  end

  it "returns failure for missing challenge token" do
    result = described_class.call(
      user_id: user[:id],
      challenge_token: nil,
      credential: { "id" => "test" }
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Challenge token is required")
  end

  it "returns failure for missing credential" do
    result = described_class.call(
      user_id: user[:id],
      challenge_token: "some-token",
      credential: nil
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Credential is required")
  end

  it "returns failure for expired challenge token" do
    allow(Auth::Token).to receive(:decode_webauthn_challenge).and_raise(JWT::DecodeError, "expired")

    result = described_class.call(
      user_id: user[:id],
      challenge_token: "expired-token",
      credential: { "id" => "test" }
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Invalid or expired challenge")
  end
end
