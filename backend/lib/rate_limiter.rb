# typed: false
# frozen_string_literal: true

require "rack/attack"

module RateLimiter
  # Minimal in-memory cache store compatible with Rack::Attack.
  # Supports increment, read, write, and delete with TTL expiry.
  class MemoryStore
    def initialize
      @data = {}
      @expires_at = {}
    end

    def read(key)
      sweep(key)
      @data[key]
    end

    def write(key, value, expires_in: nil, **)
      @data[key] = value
      @expires_at[key] = Time.now.to_f + expires_in if expires_in
    end

    def increment(key, amount = 1, expires_in: nil, **)
      sweep(key)
      @data[key] = (@data[key] || 0) + amount
      @expires_at[key] = Time.now.to_f + expires_in if expires_in && !@expires_at.key?(key)
      @data[key]
    end

    def delete(key)
      @data.delete(key)
      @expires_at.delete(key)
    end

    private

    def sweep(key)
      if (exp = @expires_at[key]) && Time.now.to_f > exp
        @data.delete(key)
        @expires_at.delete(key)
      end
    end
  end

  def self.configure!
    Rack::Attack.cache.store = MemoryStore.new

    # Skip rate limiting in test and e2e environments
    unless %w[test e2e].include?(APP_ENV)
      Rack::Attack.throttle("auth/login-link", limit: 5, period: 60) do |req|
        req.ip if req.post? && req.path == "/api/auth/login-link"
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

    Rack::Attack.throttled_callback = lambda do |req|
      matched = req.env["rack.attack.matched"]
      discriminator = req.env["rack.attack.match_discriminator"]
      APP_LOGGER.warn { "[RateLimiter] Throttled #{matched} for #{discriminator}" }
    end

    Rack::Attack.throttled_responder = lambda do |_req|
      [429, { "Content-Type" => "application/json" }, [{ error: "Rate limit exceeded. Try again later." }.to_json]]
    end
  end
end
