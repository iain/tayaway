# frozen_string_literal: true

require "spec_helper"
require "webauthn/fake_client"

RSpec.describe "AdminApp" do
  def app
    AdminApp.freeze.app
  end

  let(:user) { TestFactories.user(email: "iain@example.com") }
  let(:csrf_header) { { "HTTP_X_CSRF_PROTECTION" => "1" } }
  let(:json_headers) { csrf_header.merge("CONTENT_TYPE" => "application/json") }
  let(:fake_client) { WebAuthn::FakeClient.new("http://localhost:5173") }

  def admin_cookie(for_user = user)
    row = TestFactories.admin_session(user: for_user)
    { "HTTP_COOKIE" => "admin_session=#{row[:token]}" }
  end

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

  describe "GET /" do
    it "redirects to /login without a session" do
      get "/"

      expect(last_response.status).to eq(302)
      expect(last_response.headers["Location"]).to end_with("/login")
    end

    it "redirects to /login with an expired session" do
      row = TestFactories.admin_session(user: user, expires_at: Time.now - 60)

      get "/", {}, { "HTTP_COOKIE" => "admin_session=#{row[:token]}" }

      expect(last_response.status).to eq(302)
    end

    it "renders the dashboard with a valid admin session" do
      get "/", {}, admin_cookie

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("Tayaway admin")
      expect(last_response.body).to include("iain@example.com")
    end
  end

  describe "GET /login" do
    it "renders the login page" do
      get "/login"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("passkey")
    end

    it "redirects to the dashboard when already signed in" do
      get "/login", {}, admin_cookie

      expect(last_response.status).to eq(302)
      expect(last_response.headers["Location"]).to end_with("/")
    end
  end

  describe "POST /login/begin" do
    it "returns WebAuthn request options" do
      post "/login/begin", nil, json_headers

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["options"]).to include("challenge")
      expect(body["challengeToken"]).to be_a(String)
    end

    it "rejects a request without the CSRF header" do
      post "/login/begin", nil, { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(403)
    end
  end

  describe "POST /login/complete" do
    def complete_login
      post "/login/begin", nil, json_headers
      begin_body = JSON.parse(last_response.body)
      assertion = fake_client.get(challenge: begin_body["options"]["challenge"])

      post "/login/complete",
           { challengeToken: begin_body["challengeToken"], credential: assertion }.to_json,
           json_headers
    end

    it "sets a strict admin session cookie for an allowlisted user" do
      register_passkey

      APP_CONFIG.with(admin_emails: ["iain@example.com"]) { complete_login }

      expect(last_response.status).to eq(200)
      cookie = last_response.headers["Set-Cookie"]
      expect(cookie).to include("admin_session=")
      expect(cookie.downcase).to include("httponly")
      expect(cookie.downcase).to include("samesite=strict")

      token = cookie[/admin_session=([^;]+)/, 1]
      get "/", {}, { "HTTP_COOKIE" => "admin_session=#{token}" }
      expect(last_response.status).to eq(200)
    end

    it "returns 403 and no cookie for a user not on the allowlist" do
      register_passkey

      APP_CONFIG.with(admin_emails: ["someone-else@example.com"]) { complete_login }

      expect(last_response.status).to eq(403)
      expect(last_response.headers["Set-Cookie"].to_s).not_to include("admin_session=")
    end
  end

  describe "POST /logout" do
    it "deletes the session and clears the cookie" do
      cookie = admin_cookie

      post "/logout", nil, cookie.merge(csrf_header)

      expect(last_response.status).to eq(200)
      expect(DB[:admin_sessions].count).to eq(0)
    end

    it "requires a session" do
      post "/logout", nil, csrf_header

      expect(last_response.status).to eq(401)
    end

    it "requires the CSRF header" do
      cookie = admin_cookie

      post "/logout", nil, cookie

      expect(last_response.status).to eq(403)
      expect(DB[:admin_sessions].count).to eq(1)
    end
  end

  it "sets security headers on every response" do
    get "/login"

    expect(last_response.headers["Content-Security-Policy"]).to include("default-src 'none'")
    expect(last_response.headers["X-Frame-Options"]).to eq("DENY")
    expect(last_response.headers["X-Content-Type-Options"]).to eq("nosniff")
  end
end
