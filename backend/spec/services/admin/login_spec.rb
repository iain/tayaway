# frozen_string_literal: true

require "spec_helper"
require "webauthn/fake_client"

RSpec.describe "Admin passkey login" do
  let(:fake_client) { WebAuthn::FakeClient.new("http://localhost:9393") }

  define_method(:enroll) do |client: fake_client|
    options = Admin::BeginEnrollment.call(authenticated: false).value!
    credential = client.create(challenge: options[:options][:challenge])
    Admin::CompleteEnrollment.call(
      challenge_token: options[:challengeToken],
      credential: credential,
      nickname: "Test Key",
      authenticated: false
    ).value!
  end

  define_method(:begin_and_get) do |client: fake_client|
    options = Admin::BeginLogin.call.value!
    assertion = client.get(challenge: options[:options][:challenge])
    [options[:challengeToken], assertion]
  end

  it "logs in with an enrolled passkey and creates an admin session" do
    enroll
    challenge_token, assertion = begin_and_get

    result = Admin::CompleteLogin.call(challenge_token: challenge_token, credential: assertion)

    expect(result.success?).to be true
    value = result.value!
    session = AdminSession.find_valid(value[:token])
    expect(session).not_to be_nil
    expect(session.credential_id).to eq(Admin::State.db[:admin_credentials].first[:id])
    expect(value[:expires_at]).to be_within(60).of(Time.now + AdminSession::EXPIRY_SECONDS)
    credential_row = Admin::State.db[:admin_credentials].first
    expect(credential_row[:sign_count]).to be > 0
    expect(credential_row[:last_used_at]).not_to be_nil
  end

  it "rejects a passkey that was never enrolled" do
    enroll
    stranger = WebAuthn::FakeClient.new("http://localhost:9393")
    stranger.create(challenge: WebAuthn::Credential.options_for_create(
      user: { id: "x", name: "x" }, relying_party: Admin::RelyingParty.instance
    ).challenge
                   )
    challenge_token, assertion = begin_and_get(client: stranger)

    result = Admin::CompleteLogin.call(challenge_token: challenge_token, credential: assertion)

    expect(result.failure?).to be true
    expect(result.failure.code).to eq(:unauthorized)
    expect(Admin::State.db[:admin_sessions].count).to eq(0)
  end

  it "rejects a main-app authentication challenge token" do
    enroll
    main_options = Auth::Passkeys::BeginAuthentication.call.value!
    assertion = fake_client.get(challenge: main_options[:options][:challenge])

    result = Admin::CompleteLogin.call(
      challenge_token: main_options[:challengeToken],
      credential: assertion
    )

    expect(result.failure?).to be true
    expect(result.failure.code).to eq(:unauthorized)
    expect(Admin::State.db[:admin_sessions].count).to eq(0)
  end

  it "sweeps expired sessions when a login succeeds" do
    credential_id = enroll[:id]
    Admin::State.db[:admin_sessions].insert(
      token: Auth::Token.digest("stale"),
      credential_id: credential_id,
      created_at: Time.now - 86_400,
      expires_at: Time.now - 60
    )

    expect(AdminSession.find_valid("stale")).to be_nil

    challenge_token, assertion = begin_and_get
    Admin::CompleteLogin.call(challenge_token: challenge_token, credential: assertion).value!

    tokens = Admin::State.db[:admin_sessions].select_map(:token)
    expect(tokens).not_to include(Auth::Token.digest("stale"))
    expect(tokens.length).to eq(1)
  end
end
