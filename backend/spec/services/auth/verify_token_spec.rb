# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Auth::VerifyToken do
  it "returns failure when params are missing" do
    result = described_class.call(token: nil, email: "test@example.com")

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Token and email are required")
  end

  it "returns failure for invalid token" do
    create(:user, email: "test@example.com")

    result = described_class.call(token: "invalid", email: "test@example.com")

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Invalid or expired magic link")
    expect(result.failure.http_status).to eq(401)
  end

  it "returns session token for valid magic link and marks token as used" do
    user = create(:user, email: "test@example.com")
    magic_token = MagicLinkToken.generate_for_user(user)

    result = described_class.call(token: magic_token.token, email: "test@example.com")

    expect(result.success?).to be true
    expect(result.value![:session_token]).to be_a(String)
    expect(result.value![:user][:email]).to eq("test@example.com")
    expect(magic_token.reload.used_at).not_to be_nil
    expect(Session.where(user_id: user.id).count).to eq(1)
  end
end
