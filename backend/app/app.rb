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

  def current_session
    token = request.cookies["session_token"]
    return nil unless token

    Session.find_valid(token)
  end

  def current_user
    session = current_session
    return nil unless session

    User.find(session.user_id)
  end

  def member_of_workspace?(workspace_id)
    return false unless current_user

    WorkspaceMembership.find_by_workspace_and_user(workspace_id, current_user.id) != nil
  end

  route do |r|
    r.hash_routes
  end
end
