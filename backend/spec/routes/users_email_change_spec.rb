# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Email change endpoints" do
  before { allow(Mailers::EmailChange).to receive(:send_email) }

  let(:user) { TestFactories.user(email: "old@example.com") }
  let(:session) { TestFactories.session(user: user) }
  let(:auth_cookie) { { "HTTP_COOKIE" => "session_token=#{session[:token]}" } }
  let(:csrf_header) { { "HTTP_X_CSRF_PROTECTION" => "1" } }
  let(:json_headers) { { "CONTENT_TYPE" => "application/json" }.merge(auth_cookie).merge(csrf_header) }

  describe "POST /api/users/email-change/request" do
    it "returns 401 without auth" do
      post "/api/users/email-change/request", { email: "new@example.com" }.to_json,
           "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(401)
    end

    it "returns success for valid request, 400 for same and taken email" do
      TestFactories.user(email: "taken@example.com")

      # Valid request
      post "/api/users/email-change/request", { email: "new@example.com" }.to_json, json_headers
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["message"]).to include("verification link has been sent")

      # Same email
      post "/api/users/email-change/request", { email: "old@example.com" }.to_json, json_headers
      expect(last_response.status).to eq(400)
      expect(JSON.parse(last_response.body)["error"]).to include("different")

      # Taken email
      post "/api/users/email-change/request", { email: "taken@example.com" }.to_json, json_headers
      expect(last_response.status).to eq(400)
      expect(JSON.parse(last_response.body)["error"]).to include("already in use")
    end
  end

  describe "POST /api/users/email-change/verify" do
    it "does not require auth and returns proper errors" do
      # Invalid JWT — service 401, not auth middleware 401
      post "/api/users/email-change/verify", { token: "invalid" }.to_json,
           "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(401)
      expect(JSON.parse(last_response.body)["error"]).to include("Invalid or expired")

      # Missing token
      post "/api/users/email-change/verify", {}.to_json,
           "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(400)
    end

    it "returns success for valid token and updates email" do
      workspace = TestFactories.workspace
      TestFactories.workspace_membership(workspace: workspace, user: user)

      email_token = TestFactories.email_change_token(user: user, email: "old@example.com", new_email: "new@example.com")
      jwt = Auth::Token.encode_email_change(token: email_token.token, email: "new@example.com")

      post "/api/users/email-change/verify", { token: jwt }.to_json,
           "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["message"]).to include("email has been updated")
      expect(DB[:users].where(id: user[:id]).first[:email]).to eq("new@example.com")
    end
  end
end
