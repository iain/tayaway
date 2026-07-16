# frozen_string_literal: true

require "spec_helper"
require "webauthn/fake_client"

RSpec.describe Admin::CompleteLogin do
  let(:user) { TestFactories.user(email: "iain@example.com") }
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

  it "creates an admin session for an allowlisted user" do
    register_passkey
    challenge_token, assertion = begin_and_get

    result = APP_CONFIG.with(admin_emails: ["iain@example.com"]) do
      described_class.call(challenge_token: challenge_token, credential: assertion)
    end

    expect(result.success?).to be true
    value = result.value!
    session = AdminSession.find_valid(value[:token])
    expect(session).not_to be_nil
    expect(session.user_id.to_s).to eq(user[:id])
    expect(value[:expires_at]).to be_within(60).of(Time.now + AdminSession::EXPIRY_SECONDS)
  end

  it "matches the allowlist case-insensitively" do
    register_passkey
    challenge_token, assertion = begin_and_get

    result = APP_CONFIG.with(admin_emails: ["IAIN@Example.com"]) do
      described_class.call(challenge_token: challenge_token, credential: assertion)
    end

    expect(result.success?).to be true
  end

  it "rejects an authenticated user who is not on the allowlist" do
    register_passkey
    challenge_token, assertion = begin_and_get

    result = APP_CONFIG.with(admin_emails: ["someone-else@example.com"]) do
      described_class.call(challenge_token: challenge_token, credential: assertion)
    end

    expect(result.failure?).to be true
    expect(result.failure.code).to eq(:forbidden)
    expect(DB[:admin_sessions].count).to eq(0)
  end

  it "rejects everyone when the allowlist is empty (the default)" do
    register_passkey
    challenge_token, assertion = begin_and_get

    result = described_class.call(challenge_token: challenge_token, credential: assertion)

    expect(result.failure?).to be true
    expect(result.failure.code).to eq(:forbidden)
    expect(DB[:admin_sessions].count).to eq(0)
  end

  it "rejects an unrecognized passkey" do
    other_client = WebAuthn::FakeClient.new("http://localhost:5173")
    other_client.create(challenge: WebAuthn::Credential.options_for_create(
      user: { id: "other", name: "other@example.com" }
    ).challenge
                       )

    auth_result = Auth::Passkeys::BeginAuthentication.call
    options = auth_result.value!
    assertion = other_client.get(challenge: options[:options][:challenge])

    result = APP_CONFIG.with(admin_emails: ["iain@example.com"]) do
      described_class.call(challenge_token: options[:challengeToken], credential: assertion)
    end

    expect(result.failure?).to be true
    expect(result.failure.code).to eq(:unauthorized)
    expect(DB[:admin_sessions].count).to eq(0)
  end
end
