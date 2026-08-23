# frozen_string_literal: true

require "spec_helper"

RSpec.describe SecurityHeaders do
  def response_for(status, headers)
    inner = ->(_env) { [status, headers.dup, [""]] }
    _status, out, _body = described_class.new(inner).call({})
    out
  end

  it "leaves HTML alone" do
    # The backend serves HTML only in development, when a locally built
    # frontend/dist happens to exist and App falls through to `r.public`.
    # In production documents come from the static container, under the CSP
    # the frontend build actually needs. Stamping the JSON CSP on a document
    # would break that page and teach nobody anything.
    headers = response_for(200, { "Content-Type" => "text/html; charset=utf-8" })

    expect(headers).not_to have_key("Content-Security-Policy")
    expect(headers).not_to have_key("X-Content-Type-Options")
  end

  it "does not clobber a header the app set deliberately" do
    set_by_the_app = { "Content-Type" => "application/json", "Referrer-Policy" => "no-referrer" }

    headers = response_for(200, set_by_the_app)

    expect(headers["Referrer-Policy"]).to eq("no-referrer")
  end

  it "hardens a response with no content type at all" do
    headers = response_for(204, {})

    expect(headers["X-Content-Type-Options"]).to eq("nosniff")
  end
end
