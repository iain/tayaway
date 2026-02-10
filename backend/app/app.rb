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
  plugin :websockets

  Sequel.extension(:pg_json_ops)

  Dir[File.expand_path("routes/**/*.rb", __dir__)].each { |f| require f }

  def current_session
    auth_header = request.headers["Authorization"]
    return nil unless auth_header

    token = auth_header.sub(/^Bearer\s+/, "")
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
