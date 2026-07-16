# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Client protocol version gate" do
  describe "when the server requires a newer client" do
    before { stub_const("ClientProtocol::MIN_SUPPORTED_VERSION", 3) }

    it "returns 426 with the minimum version for an older client" do
      get "/api/auth/me", {}, { "HTTP_X_CLIENT_VERSION" => "2" }

      expect(last_response.status).to eq(426)
      expect(JSON.parse(last_response.body)).to eq(
        "error" => "Client update required",
        "minSupportedVersion" => 3
      )
    end

    it "returns 426 for a client that sends no version header" do
      header "X-Client-Version", nil
      get "/api/auth/me"

      expect(last_response.status).to eq(426)
    end

    it "gates mutating requests too" do
      post "/api/auth/login-link",
           { email: "test@example.com" }.to_json,
           { "CONTENT_TYPE" => "application/json", "HTTP_X_CLIENT_VERSION" => "2" }

      expect(last_response.status).to eq(426)
    end

    # 401, not 426: the gate passed and normal routing (auth) took over
    it "allows a client at exactly the minimum" do
      get "/api/auth/me", {}, { "HTTP_X_CLIENT_VERSION" => "3" }

      expect(last_response.status).to eq(401)
    end

    it "allows a newer client" do
      get "/api/auth/me", {}, { "HTTP_X_CLIENT_VERSION" => "4" }

      expect(last_response.status).to eq(401)
    end

    it "does not gate non-API paths" do
      get "/health"

      expect(last_response.status).to eq(200)
    end

    it "does not gate /api/health — external monitors poll it without the header" do
      get "/api/health"

      expect(last_response.status).to eq(200)
    end
  end

  describe "with the shipped minimum of 2" do
    it "gates pre-versioning clients, which send no header" do
      header "X-Client-Version", nil
      get "/api/auth/me"

      expect(last_response.status).to eq(426)
    end
  end

  describe "recording the client version on the session" do
    # Recording happens after the gate; pin the minimum to 0 so the
    # pre-versioning (headerless → 0) recording path stays testable.
    before { stub_const("ClientProtocol::MIN_SUPPORTED_VERSION", 0) }

    let(:user) { TestFactories.user }
    let(:session) { TestFactories.session(user: user) }
    let(:auth_cookie) { { "HTTP_COOKIE" => "session_token=#{session[:token]}" } }

    def recorded_version
      DB[:sessions].where(id: session[:id]).get(:last_seen_client_version)
    end

    it "records the version an authenticated request advertises" do
      get "/api/auth/me", {}, auth_cookie.merge("HTTP_X_CLIENT_VERSION" => "7")

      expect(last_response.status).to eq(200)
      expect(recorded_version).to eq(7)
    end

    it "records 0 for an authenticated request without a version header" do
      header "X-Client-Version", nil
      get "/api/auth/me", {}, auth_cookie

      expect(last_response.status).to eq(200)
      expect(recorded_version).to eq(0)
    end

    it "tracks the newest version a session's client reports" do
      get "/api/auth/me", {}, auth_cookie.merge("HTTP_X_CLIENT_VERSION" => "7")
      get "/api/auth/me", {}, auth_cookie.merge("HTTP_X_CLIENT_VERSION" => "8")

      expect(recorded_version).to eq(8)
    end

    it "does not regress when a stale tab reports an older version" do
      # An installed PWA and a not-yet-reloaded tab share the session cookie
      # but can run different bundles; the newest advertised version wins.
      get "/api/auth/me", {}, auth_cookie.merge("HTTP_X_CLIENT_VERSION" => "8")
      get "/api/auth/me", {}, auth_cookie.merge("HTTP_X_CLIENT_VERSION" => "7")

      expect(recorded_version).to eq(8)
    end
  end
end
