# frozen_string_literal: true

# Rack middleware that stamps tayaway's application security headers onto
# backend responses.
#
# These used to come from the edge's Caddy vhost, which set them once for the
# whole site — proxied API responses included. That vhost is splitting: the
# shared edge is the platform's and keeps routing, TLS and HSTS, while
# application policy headers move into tayaway's own containers, next to the
# builds that determine them. The SPA's half lives in
# containers/Caddyfile.static; this is the API's.
#
# Middleware rather than Roda's :default_headers plugin (which the admin site
# uses) because every auth, CSRF and protocol-version refusal in App is a
# `request.halt` with a literal Rack triplet, which never touches Roda's
# response object — :default_headers would skip exactly the responses an
# attacker sees most of.
#
# Mounted on App itself rather than in config.ru, so that every route spec
# runs through it. Rack::Attack is the one thing that sits outside Roda, and
# it hardens its own throttle response from HEADERS below (lib/rate_limiter.rb).
class SecurityHeaders
  # Nothing this middleware covers is ever parsed as a document — JSON bodies,
  # WebSocket upgrades, empty 204s — so the policy denies everything outright
  # rather than mirroring the SPA's. `frame-ancestors 'none'` is the half that
  # does real work here: it is the modern X-Frame-Options and, unlike it, is
  # honoured for nested browsing contexts.
  HEADERS = {
    "Content-Security-Policy" =>
      "default-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
    "X-Content-Type-Options" => "nosniff",
    "X-Frame-Options" => "DENY",
    "Referrer-Policy" => "strict-origin-when-cross-origin"
  }.freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    apply(headers) unless html?(headers)
    [status, headers, body]
  end

  private

  # `||=` rather than assignment: a route that sets one of these deliberately
  # (a download wanting its own Referrer-Policy, say) keeps its value, and the
  # middleware only fills the gaps.
  def apply(headers)
    HEADERS.each { |field, value| headers[field] ||= value }
  end

  # The backend serves HTML only in development, when a locally built
  # frontend/dist happens to exist and App falls through to `r.public`. In
  # production documents come from the static container under the CSP the
  # frontend actually needs; stamping the deny-everything policy on a document
  # would break that page and teach nobody anything.
  def html?(headers)
    headers["Content-Type"].to_s.start_with?("text/html")
  end
end
