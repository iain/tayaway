# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "POST /api/csp-report" do
  let(:csp_report_headers) { { "CONTENT_TYPE" => "application/csp-report" } }

  define_method(:valid_report) do |overrides = {}|
    {
      "csp-report" => {
        "blocked-uri" => "https://evil.example.com/script.js",
        "violated-directive" => "script-src 'self'",
        "document-uri" => "https://tayaway.nl/",
        "source-file" => "https://tayaway.nl/assets/app.js",
        "line-number" => 42
      }.merge(overrides)
    }.to_json
  end

  it "returns 204 and logs the violation" do
    expect(APP_LOGGER).to receive(:warn)

    post "/api/csp-report", valid_report, csp_report_headers

    expect(last_response.status).to eq(204)
  end

  it "returns 204 without logging for chrome-extension:// blocked-uri" do
    expect(APP_LOGGER).not_to receive(:warn)

    post "/api/csp-report",
         valid_report("blocked-uri" => "chrome-extension://abc/inject.js"),
         csp_report_headers

    expect(last_response.status).to eq(204)
  end

  it "returns 204 without logging for moz-extension:// blocked-uri" do
    expect(APP_LOGGER).not_to receive(:warn)

    post "/api/csp-report",
         valid_report("blocked-uri" => "moz-extension://xyz/content.js"),
         csp_report_headers

    expect(last_response.status).to eq(204)
  end

  it "returns 400 for invalid JSON" do
    post "/api/csp-report", "not-json", csp_report_headers

    expect(last_response.status).to eq(400)
    expect(JSON.parse(last_response.body)["error"]).to eq("Invalid report")
  end

  it "does not require authentication" do
    post "/api/csp-report", valid_report, csp_report_headers

    expect(last_response.status).not_to eq(401)
  end

  it "handles missing csp-report key gracefully" do
    expect(APP_LOGGER).to receive(:warn)

    post "/api/csp-report", {}.to_json, csp_report_headers

    expect(last_response.status).to eq(204)
  end
end
