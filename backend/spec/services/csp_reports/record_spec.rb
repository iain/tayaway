# frozen_string_literal: true

require "spec_helper"

RSpec.describe CspReports::Record do
  def csp_report_body(overrides = {})
    {
      "csp-report" => {
        "document-uri" => "https://tayaway.nl/events/abc",
        "referrer" => "",
        "violated-directive" => "script-src",
        "effective-directive" => "script-src",
        "original-policy" => "default-src 'self'",
        "disposition" => "enforce",
        "blocked-uri" => "https://evil.example/x.js",
        "line-number" => 12,
        "source-file" => "https://tayaway.nl/assets/index-abc.js",
        "status-code" => 200,
        "script-sample" => ""
      }.merge(overrides)
    }.to_json
  end

  def reports_json_body(overrides = {})
    [{
      "type" => "csp-violation",
      "age" => 12,
      "url" => "https://tayaway.nl/events/abc",
      "user_agent" => "Mozilla/5.0",
      "body" => {
        "documentURL" => "https://tayaway.nl/events/abc",
        "disposition" => "enforce",
        "effectiveDirective" => "img-src",
        "blockedURL" => "https://cdn.example/logo.png?token=secret",
        "originalPolicy" => "default-src 'self'",
        "statusCode" => 200
      }.merge(overrides)
    }].to_json
  end

  it "stores one aggregated row per distinct violation" do
    result = described_class.call(body: csp_report_body)

    expect(result.success?).to be(true)
    row = DB[:csp_reports].first
    expect(row).to include(
      disposition: "enforce",
      directive: "script-src",
      blocked_uri: "https://evil.example",
      document_uri: "/events/abc",
      count: 1
    )
    expect(row[:sample].to_h).to include("lineNumber" => 12, "sourceFile" => "https://tayaway.nl/assets/index-abc.js")
  end

  it "counts a repeat violation on the existing row" do
    described_class.call(body: csp_report_body, now: Time.now - 60)
    described_class.call(body: csp_report_body("line-number" => 40))

    expect(DB[:csp_reports].count).to eq(1)
    row = DB[:csp_reports].first
    expect(row[:count]).to eq(2)
    expect(row[:last_seen_at]).to be > row[:first_seen_at]
    # The sample tracks the latest hit, not the first.
    expect(row[:sample]["lineNumber"]).to eq(40)
  end

  it "accepts the Reporting API batch format and drops query strings" do
    described_class.call(body: reports_json_body)

    row = DB[:csp_reports].first
    expect(row).to include(directive: "img-src", blocked_uri: "https://cdn.example", document_uri: "/events/abc")
    expect(row[:sample]["userAgent"]).to eq("Mozilla/5.0")
  end

  it "ignores non-CSP entries in a Reporting API batch" do
    body = [{ "type" => "deprecation", "body" => { "id" => "SomeApi" } }].to_json

    expect(described_class.call(body: body).value!).to eq(0)
    expect(DB[:csp_reports]).to be_empty
  end

  it "drops browser-extension noise" do
    described_class.call(body: csp_report_body("blocked-uri" => "chrome-extension://abcdef/inject.js"))

    expect(DB[:csp_reports]).to be_empty
  end

  it "drops reports naming a directive no browser would send" do
    described_class.call(body: csp_report_body("effective-directive" => "made-up-src", "violated-directive" => ""))

    expect(DB[:csp_reports]).to be_empty
  end

  it "keeps inline and eval keywords as-is" do
    described_class.call(body: csp_report_body("blocked-uri" => "inline"))

    expect(DB[:csp_reports].first[:blocked_uri]).to eq("inline")
  end

  it "rejects a malformed body" do
    result = described_class.call(body: "not json")

    expect(result.failure?).to be(true)
    expect(result.failure.http_status).to eq(400)
  end

  it "rejects a body over the size cap without parsing it" do
    result = described_class.call(body: "x" * (described_class::MAX_BODY_BYTES + 1))

    expect(result.failure?).to be(true)
  end

  it "stops recording new distinct violations past the row cap" do
    stub_const("CspReports::Record::MAX_ROWS", 1)
    described_class.call(body: csp_report_body)

    described_class.call(body: csp_report_body("blocked-uri" => "https://other.example/x.js"))

    expect(DB[:csp_reports].map { |r| r[:blocked_uri] }).to eq(["https://evil.example"])
  end
end
