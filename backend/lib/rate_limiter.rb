# typed: false
# frozen_string_literal: true

require "rack/attack"

# Skip rate limiting in test and e2e environments
unless %w[test e2e].include?(APP_ENV)
  Rack::Attack.throttle("auth/magic-link", limit: 5, period: 60) do |req|
    req.ip if req.post? && req.path == "/api/auth/magic-link"
  end

  Rack::Attack.throttle("auth/verify", limit: 10, period: 60) do |req|
    req.ip if req.post? && req.path == "/api/auth/verify"
  end

  Rack::Attack.throttle("auth/ws-ticket", limit: 20, period: 60) do |req|
    req.ip if req.post? && req.path == "/api/auth/ws-ticket"
  end

  Rack::Attack.throttle("invites/accept", limit: 5, period: 60) do |req|
    req.ip if req.post? && req.path == "/api/invites/accept"
  end

  Rack::Attack.throttle("email-change/request", limit: 5, period: 60) do |req|
    req.ip if req.post? && req.path == "/api/users/email-change/request"
  end

  Rack::Attack.throttle("invites/create", limit: 10, period: 60) do |req|
    req.ip if req.post? && req.path == "/api/invites"
  end
end

Rack::Attack.throttled_responder = lambda do |_req|
  [429, { "Content-Type" => "application/json" }, [{ error: "Rate limit exceeded. Try again later." }.to_json]]
end
