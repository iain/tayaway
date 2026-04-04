# typed: false
# frozen_string_literal: true

require "rack/attack"

module RateLimiter
  # PostgreSQL-backed cache store compatible with Rack::Attack.
  # Uses the `rate_limits` table for atomic, shared-state rate limiting
  # that works correctly across multiple Falcon workers and survives restarts.
  #
  # Expired rows are cleaned up opportunistically on read/increment. A periodic
  # cleanup of all expired rows runs on every 100th increment to keep the table small.
  class PgStore
    CLEANUP_INTERVAL = 100

    def initialize
      @increment_count = 0
    end

    def read(key)
      row = DB[:rate_limits].where(key: key).where { expires_at > Time.now }.first
      row&.[](:count)
    end

    def write(key, value, expires_in: nil, **)
      expires_at = expires_in ? Time.now + expires_in : Time.now + 120
      DB[:rate_limits]
        .insert_conflict(target: :key, update: { count: value, expires_at: expires_at })
        .insert(key: key, count: value, expires_at: expires_at)
    end

    def increment(key, amount = 1, expires_in: nil, **)
      expires_at = expires_in ? Time.now + expires_in : Time.now + 120

      # Atomic upsert: insert with count=amount, or increment existing if not expired.
      # If the row is expired, reset count to the new amount with a fresh expiry.
      result = DB[<<~SQL, key, amount, expires_at, amount, amount, expires_at].first
        INSERT INTO rate_limits (key, count, expires_at)
        VALUES (?, ?, ?)
        ON CONFLICT (key) DO UPDATE SET
          count = CASE
            WHEN rate_limits.expires_at <= NOW() THEN ?
            ELSE rate_limits.count + ?
          END,
          expires_at = CASE
            WHEN rate_limits.expires_at <= NOW() THEN ?
            ELSE rate_limits.expires_at
          END
        RETURNING count
      SQL

      maybe_cleanup
      result[:count]
    end

    def delete(key)
      DB[:rate_limits].where(key: key).delete
    end

    private

    def maybe_cleanup
      @increment_count += 1
      return unless @increment_count >= CLEANUP_INTERVAL

      @increment_count = 0
      DB[:rate_limits].where { expires_at <= Time.now }.delete
    end
  end

  def self.configure!
    Rack::Attack.cache.store = PgStore.new

    # Skip rate limiting in test and e2e environments
    unless %w[test e2e].include?(APP_ENV)
      Rack::Attack.throttle("auth/login-link", limit: 5, period: 60) do |req|
        req.ip if req.post? && req.path == "/api/auth/login-link"
      end

      # Per-email rate limit: prevents targeted harassment of a single email address
      # regardless of source IP (3 requests per hour per email)
      Rack::Attack.throttle("auth/login-link/email", limit: 3, period: 3600) do |req|
        if req.post? && req.path == "/api/auth/login-link"
          body = req.body.read
          req.env["rack.input"] = StringIO.new(body)
          email = begin
            JSON.parse(body)["email"]&.strip&.downcase
          rescue StandardError
            nil
          end
          email if email && !email.empty?
        end
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

      Rack::Attack.throttle("auth/passkeys/authenticate", limit: 10, period: 60) do |req|
        req.ip if req.post? && req.path.start_with?("/api/auth/passkeys/authenticate")
      end

      Rack::Attack.throttle("auth/passkeys/register", limit: 10, period: 60) do |req|
        req.ip if req.post? && req.path.start_with?("/api/auth/passkeys/register")
      end

    end

    Rack::Attack.throttled_responder = lambda do |req|
      matched = req.env["rack.attack.matched"]
      discriminator = req.env["rack.attack.match_discriminator"]
      APP_LOGGER.warn { "[RateLimiter] Throttled #{matched} for #{discriminator}" }
      [429, { "Content-Type" => "application/json" }, [{ error: "Rate limit exceeded. Try again later." }.to_json]]
    end
  end
end
