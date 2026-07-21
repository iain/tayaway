# frozen_string_literal: true

require "spec_helper"
require "webauthn/fake_client"

RSpec.describe "Admin passkey enrollment" do
  let(:fake_client) { WebAuthn::FakeClient.new("http://localhost:9393") }

  define_method(:enroll) do |nickname: "MacBook", authenticated: false, client: fake_client|
    begin_result = Admin::BeginEnrollment.call(authenticated: authenticated)
    options = begin_result.value!
    credential = client.create(challenge: options[:options][:challenge])
    Admin::CompleteEnrollment.call(
      challenge_token: options[:challengeToken],
      credential: credential,
      nickname: nickname,
      authenticated: authenticated
    )
  end

  it "enrolls the first passkey while the store is empty" do
    result = enroll(nickname: "MacBook")

    expect(result.success?).to be true
    row = Admin::State.db[:admin_credentials].first
    expect(row[:nickname]).to eq("MacBook")
    expect(row[:external_id]).not_to be_empty
    expect(row[:public_key]).not_to be_empty
  end

  it "refuses unauthenticated enrollment once a credential exists" do
    enroll

    begin_result = Admin::BeginEnrollment.call(authenticated: false)

    expect(begin_result.failure?).to be true
    expect(begin_result.failure.code).to eq(:forbidden)
  end

  it "re-checks the store at completion, not just at begin" do
    # Two first-boot tabs: both get options while the store is empty, the
    # slower one must not slip through after the first has enrolled.
    begin_result = Admin::BeginEnrollment.call(authenticated: false)
    options = begin_result.value!
    credential = fake_client.create(challenge: options[:options][:challenge])
    enroll(client: WebAuthn::FakeClient.new("http://localhost:9393"))

    result = Admin::CompleteEnrollment.call(
      challenge_token: options[:challengeToken],
      credential: credential,
      nickname: "late tab",
      authenticated: false
    )

    expect(result.failure?).to be true
    expect(result.failure.code).to eq(:forbidden)
    expect(Admin::State.db[:admin_credentials].count).to eq(1)
  end

  it "allows an authenticated operator to add another device" do
    enroll(nickname: "MacBook")

    result = enroll(nickname: "Phone", authenticated: true,
                    client: WebAuthn::FakeClient.new("http://localhost:9393")
    )

    expect(result.success?).to be true
    expect(Admin::State.db[:admin_credentials].select_map(:nickname)).to contain_exactly("MacBook", "Phone")
  end

  it "rejects a main-app registration challenge token" do
    user = TestFactories.user
    main_begin = Auth::Passkeys::BeginRegistration.call(user_id: user[:id]).value!
    credential = fake_client.create(challenge: main_begin[:options][:challenge])

    result = Admin::CompleteEnrollment.call(
      challenge_token: main_begin[:challengeToken],
      credential: credential,
      nickname: "smuggled",
      authenticated: false
    )

    expect(result.failure?).to be true
    expect(Admin::State.db[:admin_credentials].count).to eq(0)
  end

  it "defaults a blank nickname" do
    result = enroll(nickname: "  ")

    expect(result.success?).to be true
    expect(Admin::State.db[:admin_credentials].first[:nickname]).to eq("Passkey")
  end
end
