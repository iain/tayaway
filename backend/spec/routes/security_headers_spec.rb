# frozen_string_literal: true

require "spec_helper"

# These headers used to come from the edge's Caddy vhost, which set them once
# for the whole site — proxied API responses included. That vhost is being
# split: routing and TLS become the platform's, while application policy
# headers move into tayaway's own containers (the SPA's are in
# containers/Caddyfile.static). Without this middleware the API half would
# quietly lose them at the cutover.
RSpec.describe "Security headers" do
  shared_examples "a hardened response" do
    it "refuses MIME sniffing" do
      expect(last_response.headers["X-Content-Type-Options"]).to eq("nosniff")
    end

    it "denies framing" do
      expect(last_response.headers["X-Frame-Options"]).to eq("DENY")
    end

    it "trims the referrer cross-origin" do
      expect(last_response.headers["Referrer-Policy"]).to eq("strict-origin-when-cross-origin")
    end

    it "locks the CSP down to nothing — these responses are never documents" do
      expect(last_response.headers["Content-Security-Policy"]).to eq(
        "default-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
      )
    end

    it "leaves transport security to whatever terminates TLS" do
      expect(last_response.headers).not_to have_key("Strict-Transport-Security")
    end
  end

  context "when a route answers normally" do
    before { get "/health" }

    it "answers 200" do
      expect(last_response.status).to eq(200)
    end

    it_behaves_like "a hardened response"
  end

  # The reason this is middleware rather than Roda's :default_headers plugin
  # (which the admin site uses): every auth, CSRF and protocol-version refusal
  # in App is a `request.halt` with a literal Rack triplet, which never touches
  # Roda's response object — so :default_headers would skip precisely the
  # responses an attacker sees most of.
  context "when a route halts with 401" do
    before { get "/api/auth/me" }

    it "answers 401" do
      expect(last_response.status).to eq(401)
    end

    it_behaves_like "a hardened response"
  end
end
