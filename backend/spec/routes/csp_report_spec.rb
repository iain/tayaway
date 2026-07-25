# frozen_string_literal: true

require "spec_helper"

RSpec.describe "CSP report endpoint" do
  let(:body) do
    {
      "csp-report" => {
        "document-uri" => "https://tayaway.nl/",
        "effective-directive" => "script-src",
        "blocked-uri" => "https://evil.example/x.js",
        "disposition" => "enforce"
      }
    }.to_json
  end

  # Browsers post violation reports with no session cookie, no CSRF header
  # and no X-Client-Version — the endpoint has to accept all three absences.
  it "accepts an unauthenticated, versionless report" do
    post "/api/csp-report", body, { "CONTENT_TYPE" => "application/csp-report", "HTTP_X_CLIENT_VERSION" => nil }

    expect(last_response.status).to eq(204)
    expect(last_response.body).to be_empty
    expect(DB[:csp_reports].first).to include(directive: "script-src", blocked_uri: "https://evil.example")
  end

  it "accepts a Reporting API batch" do
    batch = [{ "type" => "csp-violation",
               "body" => { "documentURL" => "https://tayaway.nl/", "effectiveDirective" => "img-src",
                           "blockedURL" => "https://cdn.example/a.png" } }].to_json

    post "/api/csp-report", batch, { "CONTENT_TYPE" => "application/reports+json" }

    expect(last_response.status).to eq(204)
    expect(DB[:csp_reports].first).to include(directive: "img-src")
  end

  it "rejects a malformed report" do
    post "/api/csp-report", "not json", { "CONTENT_TYPE" => "application/csp-report" }

    expect(last_response.status).to eq(400)
  end
end
