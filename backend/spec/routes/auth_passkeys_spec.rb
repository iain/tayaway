# typed: false
# frozen_string_literal: true

require "spec_helper"
require "webauthn/fake_client"

RSpec.describe "Auth passkeys routes" do
  let(:user) { TestFactories.user }
  let(:session) { TestFactories.session(user: user) }
  let(:auth_cookie) { { "HTTP_COOKIE" => "session_token=#{session[:token]}" } }
  let(:csrf_header) { { "HTTP_X_CSRF_PROTECTION" => "1" } }
  let(:auth_headers) { auth_cookie.merge(csrf_header) }
  let(:json_headers) { auth_headers.merge("CONTENT_TYPE" => "application/json") }
  let(:fake_client) { WebAuthn::FakeClient.new("http://localhost:5173") }

  describe "GET /api/auth/passkeys" do
    it "returns 401 without auth" do
      get "/api/auth/passkeys"

      expect(last_response.status).to eq(401)
    end

    it "returns an empty list when no passkeys exist" do
      get "/api/auth/passkeys", {}, auth_cookie

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["passkeys"]).to eq([])
    end

    it "returns the user's passkeys" do
      TestFactories.passkey_credential(user: user, name: "My Key")
      TestFactories.passkey_credential(user: user, name: "Work Key")

      get "/api/auth/passkeys", {}, auth_cookie

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["passkeys"].length).to eq(2)
      names = body["passkeys"].map { |p| p["name"] }
      expect(names).to include("My Key", "Work Key")
    end

    it "does not return other users' passkeys" do
      other_user = TestFactories.user
      TestFactories.passkey_credential(user: other_user, name: "Other Key")

      get "/api/auth/passkeys", {}, auth_cookie

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["passkeys"]).to eq([])
    end
  end

  describe "POST /api/auth/passkeys/register/begin" do
    it "returns 401 without auth" do
      post "/api/auth/passkeys/register/begin", nil, csrf_header

      expect(last_response.status).to eq(401)
    end

    it "returns WebAuthn creation options" do
      post "/api/auth/passkeys/register/begin", nil, json_headers

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["options"]).to include("challenge", "rp", "user")
      expect(body["challengeToken"]).to be_a(String)
    end
  end

  describe "POST /api/auth/passkeys/register/complete" do
    it "registers a passkey" do
      post "/api/auth/passkeys/register/begin", nil, json_headers
      begin_body = JSON.parse(last_response.body)

      credential = fake_client.create(challenge: begin_body["options"]["challenge"])

      post "/api/auth/passkeys/register/complete",
           { challengeToken: begin_body["challengeToken"], credential: credential, name: "My Key" }.to_json,
           json_headers

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["passkey"]["name"]).to eq("My Key")
      expect(body["passkey"]["id"]).to be_a(String)

      expect(DB[:passkey_credentials].where(user_id: user[:id]).count).to eq(1)
    end
  end

  describe "POST /api/auth/passkeys/authenticate/begin" do
    it "returns WebAuthn request options (no auth required)" do
      post "/api/auth/passkeys/authenticate/begin", nil, csrf_header.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["options"]).to include("challenge", "rpId")
      expect(body["challengeToken"]).to be_a(String)
    end

    it "works without CSRF header (unauthenticated endpoint)" do
      post "/api/auth/passkeys/authenticate/begin", nil, { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(200)
    end
  end

  describe "POST /api/auth/passkeys/authenticate/complete" do
    it "authenticates and sets a session cookie" do
      # Register a passkey first
      post "/api/auth/passkeys/register/begin", nil, json_headers
      begin_reg = JSON.parse(last_response.body)
      credential = fake_client.create(challenge: begin_reg["options"]["challenge"])
      post "/api/auth/passkeys/register/complete",
           { challengeToken: begin_reg["challengeToken"], credential: credential }.to_json,
           json_headers

      # Authenticate with the passkey
      post "/api/auth/passkeys/authenticate/begin", nil, csrf_header.merge("CONTENT_TYPE" => "application/json")
      begin_auth = JSON.parse(last_response.body)
      assertion = fake_client.get(challenge: begin_auth["options"]["challenge"])

      post "/api/auth/passkeys/authenticate/complete",
           { challengeToken: begin_auth["challengeToken"], credential: assertion }.to_json,
           csrf_header.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["user_id"]).to eq(user[:id])

      cookie = last_response.headers["set-cookie"]
      expect(cookie).to include("session_token=")
    end

    it "returns 401 for unrecognized credential" do
      unknown_client = WebAuthn::FakeClient.new("http://localhost:5173")
      unknown_client.create(challenge: WebAuthn::Credential.options_for_create(
        user: { id: "x", name: "x@example.com" }
      ).challenge
                           )

      post "/api/auth/passkeys/authenticate/begin", nil, csrf_header.merge("CONTENT_TYPE" => "application/json")
      begin_auth = JSON.parse(last_response.body)
      assertion = unknown_client.get(challenge: begin_auth["options"]["challenge"])

      post "/api/auth/passkeys/authenticate/complete",
           { challengeToken: begin_auth["challengeToken"], credential: assertion }.to_json,
           csrf_header.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(401)
    end
  end

  describe "PUT /api/auth/passkeys/:id" do
    it "renames a passkey" do
      passkey = TestFactories.passkey_credential(user: user, name: "Old Name")

      put "/api/auth/passkeys/#{passkey[:id]}",
          { name: "New Name" }.to_json,
          json_headers

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["passkey"]["name"]).to eq("New Name")
    end

    it "returns 400 for blank name" do
      passkey = TestFactories.passkey_credential(user: user)

      put "/api/auth/passkeys/#{passkey[:id]}",
          { name: "  " }.to_json,
          json_headers

      expect(last_response.status).to eq(400)
    end

    it "returns 404 for another user's passkey" do
      other = TestFactories.user
      passkey = TestFactories.passkey_credential(user: other)

      put "/api/auth/passkeys/#{passkey[:id]}",
          { name: "Hijack" }.to_json,
          json_headers

      expect(last_response.status).to eq(404)
    end
  end

  describe "DELETE /api/auth/passkeys/:id" do
    it "deletes a passkey" do
      passkey = TestFactories.passkey_credential(user: user, name: "Bye")

      delete "/api/auth/passkeys/#{passkey[:id]}", nil, json_headers

      expect(last_response.status).to eq(200)
      expect(DB[:passkey_credentials].where(id: passkey[:id]).count).to eq(0)
    end

    it "returns 404 for non-existent passkey" do
      delete "/api/auth/passkeys/#{SecureRandom.uuid}", nil, json_headers

      expect(last_response.status).to eq(404)
    end

    it "returns 403 for another user's passkey" do
      other = TestFactories.user
      passkey = TestFactories.passkey_credential(user: other)

      delete "/api/auth/passkeys/#{passkey[:id]}", nil, json_headers

      expect(last_response.status).to eq(403)
    end
  end
end
