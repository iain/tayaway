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
      # Simulates a TOCTOU between session lookup and user fetch: the session
      # row is valid but the user is gone. The FK cascade prevents an orphan
      # session at the SQL level (so we can't reproduce by deleting the user),
      # but the in-process race is real — stub User.find to return nil for
      # this user_id and exercise the missing-user branch in the route.
      token = session[:token]
      allow(User).to receive(:find).and_return(nil)

      get "/api/auth/me", {}, { "HTTP_COOKIE" => "session_token=#{token}" }

      expect(last_response.status).to eq(401)
      body = JSON.parse(last_response.body)
      expect(body["error"]).to eq("Invalid or expired session")
    end
  end
end
