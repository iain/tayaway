# frozen_string_literal: true

require "roda"

# The operator-only maintenance site (doc/admin.md). Runs as its own
# falcon-host process (admin/falcon.rb) behind an mTLS-gated Caddy vhost —
# it is never routed from the main app, and the main app never routes here.
#
# Server-rendered on purpose: no build step, no service worker, no offline
# queue — the PWA machinery that makes the main frontend resilient is all
# liability in a break-glass tool.
class AdminApp < Roda
  include ResultHandler

  plugin :json
  plugin :json_parser
  plugin :cookies
  plugin :render, views: File.expand_path("views", __dir__), escape: true
  plugin :public, root: File.expand_path("public", __dir__)
  # The admin site serves no third-party content and is never embedded;
  # lock the CSP down to same-origin scripts/styles and fetch calls.
  plugin :default_headers,
         "Content-Security-Policy" => "default-src 'none'; script-src 'self'; style-src 'self'; " \
                                      "connect-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'",
         "X-Content-Type-Options" => "nosniff",
         "X-Frame-Options" => "DENY",
         "Referrer-Policy" => "no-referrer"
  plugin :error_handler do |e|
    unless APP_CONFIG.test?
      APP_LOGGER.error { "[AdminApp] #{e.class}: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}" }
    end
    { error: "Internal server error" }
  end

  # __Host- prefix enforces Secure, exact host match, and Path=/ in browsers.
  # Only used in production since __Host- requires HTTPS.
  COOKIE_NAME = APP_CONFIG.production? ? "__Host-admin_session" : "admin_session"

  # Same header contract as the main app, but enforced on every mutating
  # request — all admin mutations go through fetch calls that set it, and
  # SameSite=Strict on the cookie backs it up.
  CSRF_HEADER = "HTTP_X_CSRF_PROTECTION"
  CSRF_MUTATING_METHODS = %w[POST PUT PATCH DELETE].freeze

  def verify_csrf_header!
    return unless CSRF_MUTATING_METHODS.include?(request.request_method)
    return if request.env[CSRF_HEADER] == "1"

    APP_LOGGER.warn do
      "[AdminApp] Missing X-CSRF-Protection header on #{request.request_method} #{request.path_info}"
    end
    request.halt [403, { "Content-Type" => "application/json" }, ['{"error":"Forbidden"}']]
  end

  def set_admin_cookie(token, expires_at)
    response.set_cookie(
      COOKIE_NAME,
      value: token,
      path: "/",
      httponly: true,
      secure: APP_CONFIG.production?,
      same_site: :strict,
      expires: expires_at
    )
  end

  def clear_admin_cookie
    response.set_cookie(
      COOKIE_NAME,
      value: "",
      path: "/",
      httponly: true,
      secure: APP_CONFIG.production?,
      same_site: :strict,
      expires: Time.at(0)
    )
  end

  # Memoized per request (Roda creates a new instance per request); defined?
  # caches nil results the same way the main app's current_session does.
  def current_admin_session
    return @_current_admin_session if defined?(@_current_admin_session)

    token = request.cookies[COOKIE_NAME]
    @_current_admin_session = token ? AdminSession.find_valid(token) : nil
  end

  def current_admin
    return @_current_admin if defined?(@_current_admin)

    session = current_admin_session
    @_current_admin = session ? User.find(session.user_id) : nil
  end

  # View helpers. All timestamps on the dashboard are UTC — one timezone
  # for ops means no DST head-scratchers when correlating with journald.
  def utc(time)
    time&.getutc&.strftime("%Y-%m-%d %H:%M")
  end

  def truncate(str, length = 200)
    if str.nil?
      ""
    elsif str.length > length
      "#{str[0, length]}…"
    else
      str
    end
  end

  route do |r|
    verify_csrf_header!

    r.public

    r.on "login" do
      r.is do
        r.get do
          if current_admin
            r.redirect "/"
          else
            view "login"
          end
        end
      end

      r.post "begin" do
        handle_result(Auth::Passkeys::BeginAuthentication.call)
      end

      r.post "complete" do
        result = Admin::CompleteLogin.call(
          challenge_token: r.params["challengeToken"],
          credential: r.params["credential"]
        )
        if result.success?
          set_admin_cookie(result.value![:token], result.value![:expires_at])
          { message: "ok" }
        else
          handle_result(result)
        end
      end
    end

    r.post "logout" do
      session = current_admin_session
      unless session
        request.halt [401, { "Content-Type" => "application/json" }, ['{"error":"Authorization required"}']]
      end

      DB[:admin_sessions].where(id: session.id.to_s).delete
      clear_admin_cookie
      { message: "Logged out" }
    end

    r.root do
      if current_admin
        @jobs = Admin::Stats.jobs
        @users = Admin::Stats.users
        @versions = Admin::Stats.client_versions
        @audit_outcome = Admin::Stats::AUDIT_OUTCOMES.include?(r.params["outcome"]) ? r.params["outcome"] : nil
        @audit = Admin::Stats.audit(outcome: @audit_outcome)
        view "dashboard"
      else
        r.redirect "/login"
      end
    end
  end
end
