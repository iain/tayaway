# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Auth sessions endpoints" do
  let(:user) { TestFactories.user }
  let(:session) { TestFactories.session(user: user) }
  let(:auth_cookie) { { "HTTP_COOKIE" => "session_token=#{session[:token]}" } }
  let(:csrf_header) { { "HTTP_X_CSRF_PROTECTION" => "1" } }
  let(:auth_headers) { auth_cookie.merge(csrf_header) }

  describe "GET /api/auth/sessions" do
    it "returns 401 without auth" do
      get "/api/auth/sessions"

      expect(last_response.status).to eq(401)
    end

    it "returns sessions for the current user" do
      # Create a second session
      other_session = TestFactories.session(user: user)

      get "/api/auth/sessions", {}, auth_cookie

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["sessions"].length).to eq(2)

      current = body["sessions"].find { |s| s["id"] == session[:id] }
      other = body["sessions"].find { |s| s["id"] == other_session[:id] }

      expect(current["current"]).to be true
      expect(other["current"]).to be false
    end

    it "does not return expired sessions" do
      TestFactories.session(user: user, expires_at: Time.now - 3600)

      get "/api/auth/sessions", {}, auth_cookie

      body = JSON.parse(last_response.body)
      expect(body["sessions"].length).to eq(1)
    end
  end

  describe "DELETE /api/auth/sessions/:id" do
    it "returns 401 without auth" do
      delete "/api/auth/sessions/#{SecureRandom.uuid}"

      expect(last_response.status).to eq(401)
    end

    it "deletes another session" do
      other_session = TestFactories.session(user: user)

      delete "/api/auth/sessions/#{other_session[:id]}", {}, auth_headers

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["message"]).to eq("Session ended successfully")
      expect(DB[:sessions].where(id: other_session[:id]).count).to eq(0)
    end

    it "prevents deleting the current session" do
      delete "/api/auth/sessions/#{session[:id]}", {}, auth_headers

      expect(last_response.status).to eq(400)
      body = JSON.parse(last_response.body)
      expect(body["error"]).to include("Cannot delete current session")
    end

    it "returns 404 for non-existent session" do
      delete "/api/auth/sessions/#{SecureRandom.uuid}", {}, auth_headers

      expect(last_response.status).to eq(404)
    end

    it "returns 403 for another user's session" do
      other_user = TestFactories.user
      other_session = TestFactories.session(user: other_user)

      delete "/api/auth/sessions/#{other_session[:id]}", {}, auth_headers

      expect(last_response.status).to eq(403)
    end
  end
end
