# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Auth::VerifyToken do
  it "returns failure when token is nil" do
    result = described_class.call(token: nil)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Token is required")
  end

  it "returns failure for invalid JWT" do
    result = described_class.call(token: "not-a-jwt")

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Invalid or expired magic link")
    expect(result.failure.http_status).to eq(401)
  end

  it "returns failure for expired JWT" do
    payload = { token: "sometoken", email: "test@example.com", exp: (Time.now - 60).to_i }
    expired_jwt = JWT.encode(payload, APP_SECRET, "HS256")

    result = described_class.call(token: expired_jwt)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Invalid or expired magic link")
  end

  it "returns failure for valid JWT but non-existent magic link token" do
    jwt = Auth::Token.encode_magic_link(token: "nonexistent", email: "test@example.com")

    result = described_class.call(token: jwt)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Invalid or expired magic link")
    expect(result.failure.http_status).to eq(401)
  end

  it "returns session token for valid JWT and marks token as used" do
    user = TestFactories.user(email: "test@example.com")
    magic_token = TestFactories.magic_link_token(user: user)
    jwt = Auth::Token.encode_magic_link(token: magic_token.token, email: "test@example.com")

    result = described_class.call(token: jwt)

    expect(result.success?).to be true
    expect(result.value![:session_token]).to be_a(String)
    expect(result.value![:user_id]).to eq(user[:id])
    updated_token = DB[:magic_link_tokens].where(id: magic_token.record.id).first
    expect(updated_token[:used_at]).not_to be_nil
    expect(DB[:sessions].where(user_id: user[:id]).count).to eq(1)
  end
end
