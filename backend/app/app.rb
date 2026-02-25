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

  STATIC_DIR = T.let(
    Pathname.new(ENV.fetch("STATIC_DIR", File.expand_path("../../frontend/dist", __dir__))),
    Pathname
  )

  if STATIC_DIR.directory?
    plugin :public, root: STATIC_DIR.to_s
  end

  Sequel.extension(:pg_json_ops)

  Dir[File.expand_path("routes/**/*.rb", __dir__)].each { |f| require f }

  def set_session_cookie(token, expires_at)
    response.set_cookie(
      "session_token",
      value: token,
      path: "/",
      httponly: true,
      secure: ENV["RACK_ENV"] == "production",
      same_site: :lax,
      expires: expires_at
    )
  end

  def clear_session_cookie
    response.delete_cookie("session_token", path: "/")
  end

  # Memoized per request (Roda creates a new App instance per request).
  # Uses defined? to cache nil results (no cookie / no session).
  def current_session
    return @_current_session if defined?(@_current_session)

    token = request.cookies["session_token"]
    @_current_session = token ? Session.find_valid(token) : nil
  end

  def current_user
    return @_current_user if defined?(@_current_user)

    session = current_session
    @_current_user = session ? User.find(session.user_id) : nil
  end

  def require_auth
    user = current_user
    return user if user

    request.halt [401, { "Content-Type" => "application/json" }, ['{"error":"Authorization required"}']]
  end

  def require_session
    session = current_session
    return session if session

    request.halt [401, { "Content-Type" => "application/json" }, ['{"error":"Authorization required"}']]
  end

  def member_of_workspace?(workspace_id)
    return false unless current_user

    !WorkspaceMembership.find_by_workspace_and_user(workspace_id, current_user.id).nil?
  end

  def require_admin_or_owner!(workspace_id)
    membership = WorkspaceMembership.find_by_workspace_and_user(workspace_id, current_user.id)
    return if membership && %w[admin owner].include?(membership.role)

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
