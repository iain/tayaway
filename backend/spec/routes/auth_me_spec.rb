# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Auth me endpoint" do
  let(:user) { TestFactories.user }
  let(:session) { TestFactories.session(user: user) }
  let(:auth_cookie) { { "HTTP_COOKIE" => "session_token=#{session[:token]}" } }

  describe "GET /api/auth/me" do
    it "returns 401 without auth" do
      get "/api/auth/me"

      expect(last_response.status).to eq(401)
    end

    it "returns the current user" do
      get "/api/auth/me", {}, auth_cookie

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["user_id"]).to eq(user[:id])
      expect(body["email"]).to eq(user[:email])
      expect(body["name"]).to eq(user[:name])
    end

    it "returns 401 when the user has been deleted" do
      # Force eager creation of user and session before manipulating the DB
      token = session[:token]
      user_id = user[:id]

      # Bypass FK to simulate a race condition where the user is deleted but
      # their session row survives (e.g. between the session check and user fetch)
      DB.run("SET session_replication_role = replica")
      DB[:users].where(id: user_id).delete
      DB.run("SET session_replication_role = DEFAULT")

      get "/api/auth/me", {}, { "HTTP_COOKIE" => "session_token=#{token}" }

      expect(last_response.status).to eq(401)
      body = JSON.parse(last_response.body)
      expect(body["error"]).to eq("Invalid or expired session")
    end
  end
end
