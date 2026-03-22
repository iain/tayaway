# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Auth logout endpoint" do
  let(:user) { TestFactories.user }
  let(:session) { TestFactories.session(user: user) }
  let(:auth_cookie) { { "HTTP_COOKIE" => "session_token=#{session[:token]}" } }
  let(:csrf_header) { { "HTTP_X_CSRF_PROTECTION" => "1" } }
  let(:auth_headers) { auth_cookie.merge(csrf_header) }

  describe "POST /api/auth/logout" do
    it "returns 401 without auth" do
      post "/api/auth/logout", {}, csrf_header

      expect(last_response.status).to eq(401)
    end

    it "deletes the session from the database" do
      post "/api/auth/logout", {}, auth_headers

      expect(last_response.status).to eq(200)
      expect(DB[:sessions].where(id: session[:id]).count).to eq(0)
    end

    it "clears the session cookie with all required attributes" do
      post "/api/auth/logout", {}, auth_headers

      set_cookie_header = last_response.headers["set-cookie"] || last_response.headers["Set-Cookie"]
      expect(set_cookie_header).not_to be_nil

      expect(set_cookie_header).to match(/session_token=;/)
      expect(set_cookie_header).to match(/path=\//i)
      expect(set_cookie_header).to match(/httponly/i)
      expect(set_cookie_header).to match(/samesite=lax/i)
      # Cookie expiry set to epoch (Jan 1 1970) to instruct browser to delete it
      expect(set_cookie_header).to match(/expires=.*1970/i)
    end
  end
end
