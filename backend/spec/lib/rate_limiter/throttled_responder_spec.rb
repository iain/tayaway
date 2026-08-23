# frozen_string_literal: true

require "spec_helper"

# Rack::Attack is mounted in config.ru, outside Roda — so App's SecurityHeaders
# middleware never sees a throttled response. Without this the 429 would be the
# one API response with no security headers on it, and nothing else would say so.
RSpec.describe "Rack::Attack throttled responder" do
  subject(:response) do
    RateLimiter.configure!
    env = Rack::MockRequest.env_for("/api/auth/login-link", "REMOTE_ADDR" => "203.0.113.9")
    env["rack.attack.matched"] = "auth/login-link"
    env["rack.attack.match_discriminator"] = "203.0.113.9"
    Rack::Attack.throttled_responder.call(Rack::Attack::Request.new(env))
  end

  it "answers 429 with a JSON body" do
    status, headers, body = response

    expect(status).to eq(429)
    expect(headers["Content-Type"]).to eq("application/json")
    expect(JSON.parse(body.first)).to include("error")
  end

  it "carries the same headers as every other API response" do
    _status, headers, _body = response

    expect(headers).to include(SecurityHeaders::HEADERS)
  end
end
