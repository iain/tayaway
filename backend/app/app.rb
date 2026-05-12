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
    unless APP_CONFIG.test?
      $stderr.puts "Unhandled error: #{e.class}: #{e.message}"
      e.backtrace&.each { |line| $stderr.puts line }
    end
    { error: "Internal server error" }
  end

  STATIC_DIR = Pathname.new(APP_CONFIG.static_dir || File.expand_path("../../frontend/dist", __dir__))

  plugin :public, root: STATIC_DIR.to_s

  Sequel.extension(:pg_json_ops)

  Dir[File.expand_path("routes/**/*.rb", __dir__)].each { |f| require f }

  # __Host- prefix enforces Secure, exact host match, and Path=/ in browsers.
  # Only used in production since __Host- requires HTTPS.
  COOKIE_NAME = APP_CONFIG.production? ? "__Host-session_token" : "session_token"

  def set_session_cookie(token, expires_at)
    response.set_cookie(
      COOKIE_NAME,
      value: token,
      path: "/",
      httponly: true,
      secure: APP_CONFIG.production?,
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
      secure: APP_CONFIG.production?,
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

  CSRF_HEADER = "HTTP_X_CSRF_PROTECTION"
  CSRF_MUTATING_METHODS = %w[POST PUT PATCH DELETE].freeze

  REQUEST_ID_HEADER = "HTTP_X_REQUEST_ID"
  # Cap and character class are deliberately tight: the request id ends up
  # in log lines, audit rows, and (potentially) external systems, so we
  # don't want clients smuggling control characters or absurdly long
  # values into any of them. Anything that doesn't match gets replaced
  # with a generated UUID — we never reject the request over a header.
  REQUEST_ID_PATTERN = /\A[A-Za-z0-9_-]{1,128}\z/
  private_constant :REQUEST_ID_PATTERN

  def self.resolve_request_id(env)
    raw = env[REQUEST_ID_HEADER]
    return raw if raw.is_a?(String) && raw.match?(REQUEST_ID_PATTERN)

    SecureRandom.uuid
  end

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

  def current_membership(workspace_id = nil)
    return @_current_membership if @_current_membership && workspace_id.nil?
    return nil unless current_user && workspace_id

    @_current_membership = WorkspaceMembership.find_by_workspace_and_user(workspace_id, current_user.id)
  end

  def member_of_workspace?(workspace_id)
    !current_membership(workspace_id).nil?
  end

  def require_admin_or_owner!(workspace_id)
    membership = WorkspaceMembership.find_by_workspace_and_user(workspace_id, current_user.id)
    return if membership && %w[admin owner].include?(membership.role)

    APP_LOGGER.warn { "[Auth] Forbidden: user #{current_user.id} lacks admin/owner role for workspace #{workspace_id} on #{request.request_method} #{request.path_info}" }
    request.halt [403, { "Content-Type" => "application/json" }, ['{"error":"Admin or owner role required"}']]
  end

  route do |r|
    request_id = App.resolve_request_id(r.env)
    # Echo the resolved id back so clients and on-call can pull it out of
    # a failed response and find the matching server-side logs.
    response.headers["X-Request-ID"] = request_id

    RequestContext.with(request_id: request_id) do
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
end
