# typed: true
# frozen_string_literal: true

require "roda"

class App < Roda
  include ResultHandler

  plugin :json
  plugin :json_parser
  plugin :hash_routes
  plugin :request_headers
  plugin :all_verbs
  plugin :cookies
  plugin :websockets
  plugin :error_handler do |e|
    unless APP_ENV == "test"
      $stderr.puts "Unhandled error: #{e.class}: #{e.message}"
      e.backtrace&.each { |line| $stderr.puts line }
    end
    { error: "Internal server error" }
  end

  STATIC_DIR = T.let(
    Pathname.new(ENV.fetch("STATIC_DIR", File.expand_path("../../frontend/dist", __dir__))),
    Pathname
  )

  plugin :public, root: STATIC_DIR.to_s

  Sequel.extension(:pg_json_ops)

  Dir[File.expand_path("routes/**/*.rb", __dir__)].each { |f| require f }

  # __Host- prefix enforces Secure, exact host match, and Path=/ in browsers.
  # Only used in production since __Host- requires HTTPS.
  COOKIE_NAME = T.let(
    ENV["RACK_ENV"] == "production" ? "__Host-session_token" : "session_token",
    String
  )

  def set_session_cookie(token, expires_at)
    response.set_cookie(
      COOKIE_NAME,
      value: token,
      path: "/",
      httponly: true,
      secure: ENV["RACK_ENV"] == "production",
      same_site: :lax,
      expires: expires_at
    )
  end

  def clear_session_cookie
    response.set_cookie(
      COOKIE_NAME,
      value: "",
      path: "/",
      httponly: true,
      secure: ENV["RACK_ENV"] == "production",
      same_site: :lax,
      expires: Time.at(0)
    )
  end

  # Memoized per request (Roda creates a new App instance per request).
  # Uses defined? to cache nil results (no cookie / no session).
  # Throttled activity touch: updates last_active_at at most once per 5 minutes.
  def current_session
    return @_current_session if defined?(@_current_session)

    token = request.cookies[COOKIE_NAME]
    session = token ? Session.find_valid(token) : nil
    Session.touch_activity(session) if session
    @_current_session = session
  end

  def current_user
    return @_current_user if defined?(@_current_user)

    session = current_session
    @_current_user = session ? User.find(session.user_id) : nil
  end

  # Mask an IBAN for display: "NL02 •••• •••• 5678" — first 4 and last 4 visible.
  def mask_iban(iban)
    return nil if iban.nil?
    return iban if iban.length <= 8

    "#{iban[0, 4]} #{"•••• " * ((iban.length - 8) / 4)}#{iban[-4, 4]}"
  end

  CSRF_HEADER = T.let("HTTP_X_CSRF_PROTECTION", String)
  CSRF_MUTATING_METHODS = T.let(%w[POST PUT PATCH DELETE].freeze, T::Array[String])

  def verify_csrf_header!
    return unless CSRF_MUTATING_METHODS.include?(request.request_method)
    return if request.env[CSRF_HEADER] == "1"

    APP_LOGGER.warn do
      "[CSRF] Missing or invalid X-CSRF-Protection header on " \
        "#{request.request_method} #{request.path_info} from #{request.ip}"
    end
    request.halt [403, { "Content-Type" => "application/json" }, ['{"error":"Forbidden"}']]
  end

  def require_auth
    user = current_user
    unless user
      APP_LOGGER.warn { "[Auth] Unauthorized request: #{request.request_method} #{request.path_info} from #{request.ip}" }
      request.halt [401, { "Content-Type" => "application/json" }, ['{"error":"Authorization required"}']]
    end

    verify_csrf_header!
    user
  end

  def require_session
    session = current_session
    unless session
      request.halt [401, { "Content-Type" => "application/json" }, ['{"error":"Authorization required"}']]
    end

    verify_csrf_header!
    session
  end

  def member_of_workspace?(workspace_id)
    return false unless current_user

    !WorkspaceMembership.find_by_workspace_and_user(workspace_id, current_user.id).nil?
  end

  def require_admin_or_owner!(workspace_id)
    membership = WorkspaceMembership.find_by_workspace_and_user(workspace_id, current_user.id)
    return if membership && %w[admin owner].include?(membership.role)

    APP_LOGGER.warn { "[Auth] Forbidden: user #{current_user.id} lacks admin/owner role for workspace #{workspace_id} on #{request.request_method} #{request.path_info}" }
    request.halt [403, { "Content-Type" => "application/json" }, ['{"error":"Admin or owner role required"}']]
  end

  route do |r|
    r.hash_routes

    if STATIC_DIR.directory?
      r.public

      # SPA fallback: serve index.html for non-API/WS paths so Vue Router handles them
      unless r.path_info.start_with?("/api", "/ws")
        index_path = STATIC_DIR.join("index.html")
        if index_path.file?
          r.halt [200, { "Content-Type" => "text/html", "Cache-Control" => "no-cache, no-store, must-revalidate" }, [index_path.read]]
        end
      end
    end
  end
end
