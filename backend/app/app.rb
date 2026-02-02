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

  Sequel.extension(:pg_json_ops)

  Dir[File.expand_path("routes/**/*.rb", __dir__)].each { |f| require f }

  def current_user
    auth_header = request.headers["Authorization"]
    return nil unless auth_header

    token = auth_header.sub(/^Bearer\s+/, "")
    session = Session.find_valid_session(token)
    session&.user
  end

  route do |r|
    r.hash_routes
  end
end
