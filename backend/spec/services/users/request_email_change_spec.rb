# frozen_string_literal: true

require "spec_helper"

RSpec.describe Users::RequestEmailChange do
  before { allow(Mailers::EmailChange).to receive(:send_email) }

  it "validates email input" do
    user = TestFactories.user

    [nil, "", "not-an-email"].each do |bad_email|
      result = described_class.call(user_id: user[:id], new_email: bad_email)
      expect(result.failure?).to be(true), "Expected failure for email=#{bad_email.inspect}"
    end
  end

  it "rejects same email and already-taken email" do
    user = TestFactories.user(email: "current@example.com")
    TestFactories.user(email: "taken@example.com")

    same_result = described_class.call(user_id: user[:id], new_email: "current@example.com")
    expect(same_result.failure?).to be true
    expect(same_result.failure.message).to include("different")

    taken_result = described_class.call(user_id: user[:id], new_email: "taken@example.com")
    expect(taken_result.failure?).to be true
    expect(taken_result.failure.message).to include("already in use")
  end

  it "returns failure when user is not found" do
    result = described_class.call(user_id: SecureRandom.uuid, new_email: "new@example.com")

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("User not found")
  end

  it "creates token, stores correct emails, and sends verification email" do
    user = TestFactories.user(email: "old@example.com")

    result = described_class.call(user_id: user[:id], new_email: "new@example.com")

    expect(result.success?).to be true
    expect(result.value![:message]).to include("verification link has been sent")

    token_row = DB[:email_change_tokens].where(user_id: user[:id]).first
    expect(token_row[:email]).to eq("old@example.com")
    expect(token_row[:new_email]).to eq("new@example.com")
    expect(token_row[:used_at]).to be_nil

    expect(Mailers::EmailChange).to have_received(:send_email).with(
      email: an_instance_of(EmailAddress),
      verification_link: a_string_matching(%r{verify-email\?token=eyJ})
    )
  end

  it "invalidates previous pending tokens" do
    user = TestFactories.user(email: "old@example.com")

    described_class.call(user_id: user[:id], new_email: "first@example.com")
    described_class.call(user_id: user[:id], new_email: "second@example.com")

    tokens = DB[:email_change_tokens].where(user_id: user[:id]).all
    expect(tokens.length).to eq(2)
    expect(tokens.find { |t| t[:new_email] == "first@example.com" }[:used_at]).not_to be_nil
    expect(tokens.find { |t| t[:new_email] == "second@example.com" }[:used_at]).to be_nil
  end

  it "logs info when email change is requested" do
    user = TestFactories.user(email: "old@example.com")
    logged_messages = []
    allow(APP_LOGGER).to receive(:info) do |&block|
      logged_messages << block.call if block
    end

    described_class.call(user_id: user[:id], new_email: "new@example.com")

    expect(logged_messages).to include(a_string_including("[Users::RequestEmailChange]"))
  end
end
