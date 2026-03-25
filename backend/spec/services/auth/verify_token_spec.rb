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
    expect(result.failure.message).to eq("Invalid or expired login link")
    expect(result.failure.http_status).to eq(401)
  end

  it "returns failure for expired JWT" do
    payload = { token: "sometoken", email: "test@example.com", exp: (Time.now - 60).to_i }
    expired_jwt = JWT.encode(payload, APP_SECRET, "HS256")

    result = described_class.call(token: expired_jwt)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Invalid or expired login link")
  end

  it "returns failure for valid JWT but non-existent login link token" do
    jwt = Auth::Token.encode_login_link(token: "nonexistent", email: "test@example.com")

    result = described_class.call(token: jwt)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Invalid or expired login link")
    expect(result.failure.http_status).to eq(401)
  end

  it "returns session token for valid JWT and marks token as used" do
    user = TestFactories.user(email: "test@example.com")
    login_token = TestFactories.login_link_token(user: user)
    jwt = Auth::Token.encode_login_link(token: login_token.token, email: "test@example.com")

    result = described_class.call(token: jwt)

    expect(result.success?).to be true
    expect(result.value![:session_token]).to be_a(String)
    expect(result.value![:user_id]).to eq(user[:id])
    updated_token = DB[:login_link_tokens].where(id: login_token.record.id).first
    expect(updated_token[:used_at]).not_to be_nil
    expect(DB[:sessions].where(user_id: user[:id]).count).to eq(1)
  end

  it "stores browser name and OS when user_agent is provided" do
    user = TestFactories.user(email: "ua@example.com")
    login_token = TestFactories.login_link_token(user: user)
    jwt = Auth::Token.encode_login_link(token: login_token.token, email: "ua@example.com")
    chrome_ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
                "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    result = described_class.call(token: jwt, user_agent: chrome_ua)

    expect(result.success?).to be true
    session = DB[:sessions].where(user_id: user[:id]).first
    expect(session[:browser_name]).not_to be_nil
    expect(session[:os_name]).not_to be_nil
  end

  it "stores IP address when ip is provided" do
    user = TestFactories.user(email: "ip@example.com")
    login_token = TestFactories.login_link_token(user: user)
    jwt = Auth::Token.encode_login_link(token: login_token.token, email: "ip@example.com")

    result = described_class.call(token: jwt, ip: "93.184.216.34")

    expect(result.success?).to be true
    session = DB[:sessions].where(user_id: user[:id]).first
    expect(session[:ip_address]).to eq("93.184.216.34")
    # city/country may be nil when mmdb file is absent (expected in test env)
  end

  it "creates session without context when ip and user_agent are omitted" do
    user = TestFactories.user(email: "nocontext@example.com")
    login_token = TestFactories.login_link_token(user: user)
    jwt = Auth::Token.encode_login_link(token: login_token.token, email: "nocontext@example.com")

    result = described_class.call(token: jwt)

    expect(result.success?).to be true
    session = DB[:sessions].where(user_id: user[:id]).first
    expect(session[:ip_address]).to be_nil
    expect(session[:browser_name]).to be_nil
    expect(session[:os_name]).to be_nil
  end
end
