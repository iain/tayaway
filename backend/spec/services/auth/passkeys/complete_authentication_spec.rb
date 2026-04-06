# frozen_string_literal: true

require "spec_helper"
require "webauthn/fake_client"

RSpec.describe Auth::Passkeys::CompleteAuthentication do
  let(:user) { TestFactories.user }
  let(:fake_client) { WebAuthn::FakeClient.new("http://localhost:5173") }

  define_method(:register_passkey) do
    begin_result = Auth::Passkeys::BeginRegistration.call(user_id: user[:id])
    options = begin_result.value!
    credential = fake_client.create(challenge: options[:options][:challenge])
    Auth::Passkeys::CompleteRegistration.call(
      user_id: user[:id],
      challenge_token: options[:challengeToken],
      credential: credential,
      name: "Test Key"
    )
  end

  define_method(:begin_and_get) do
    auth_result = Auth::Passkeys::BeginAuthentication.call
    options = auth_result.value!
    assertion = fake_client.get(challenge: options[:options][:challenge])
    [options[:challengeToken], assertion]
  end

  it "authenticates with a registered passkey and creates a session" do
    register_passkey

    challenge_token, assertion = begin_and_get
    result = described_class.call(
      challenge_token: challenge_token,
      credential: assertion,
      ip: "127.0.0.1",
      user_agent: "Mozilla/5.0"
    )

    expect(result.success?).to be true
    value = result.value!
    expect(value[:session_token]).to be_a(String)
    expect(value[:user_id]).to eq(user[:id])

    expect(DB[:sessions].where(user_id: user[:id]).count).to eq(1)
  end

  it "updates the sign count after authentication" do
    register_passkey

    challenge_token, assertion = begin_and_get
    described_class.call(
      challenge_token: challenge_token,
      credential: assertion
    )

    passkey = DB[:passkey_credentials].where(user_id: user[:id]).first
    expect(passkey[:sign_count]).to be >= 1
  end

  it "returns failure for unrecognized credential" do
    other_client = WebAuthn::FakeClient.new("http://localhost:5173")
    other_client.create(challenge: WebAuthn::Credential.options_for_create(
      user: { id: "other", name: "other@example.com" }
    ).challenge
                       )

    auth_result = Auth::Passkeys::BeginAuthentication.call
    options = auth_result.value!
    assertion = other_client.get(challenge: options[:options][:challenge])

    result = described_class.call(
      challenge_token: options[:challengeToken],
      credential: assertion
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Passkey not recognized")
  end

  it "returns failure for missing challenge token" do
    result = described_class.call(challenge_token: nil, credential: { "id" => "x" })

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Challenge token is required")
  end

  it "returns failure for missing credential" do
    result = described_class.call(challenge_token: "tok", credential: nil)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Credential is required")
  end

  it "returns failure for tampered assertion (WebAuthn verification failure)" do
    register_passkey

    # Get a valid challenge but use a different client's assertion
    auth_result = Auth::Passkeys::BeginAuthentication.call
    options = auth_result.value!
    other_client = WebAuthn::FakeClient.new("http://localhost:5173")
    other_client.create(challenge: WebAuthn::Credential.options_for_create(
      user: { id: "other", name: "other@example.com" }
    ).challenge
                       )
    tampered = other_client.get(challenge: options[:options][:challenge])

    result = described_class.call(
      challenge_token: options[:challengeToken],
      credential: tampered
    )

    expect(result.failure?).to be true
    # Unrecognized because the credential ID doesn't match any stored passkey
    expect(result.failure.message).to eq("Passkey not recognized")
  end

  it "returns failure when user has been deleted" do
    register_passkey

    challenge_token, assertion = begin_and_get

    # Delete user between verification and session creation
    DB.run("SET session_replication_role = replica")
    DB[:users].where(id: user[:id]).delete
    DB.run("SET session_replication_role = DEFAULT")

    result = described_class.call(
      challenge_token: challenge_token,
      credential: assertion
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("User not found")
  end
end
