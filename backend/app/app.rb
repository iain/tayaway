# typed: true
# frozen_string_literal: true

require "roda"

class App < Roda
  plugin :json
  plugin :json_parser
  plugin :hash_routes
  plugin :request_headers
  plugin :all_verbs

  Sequel.extension(:pg_json_ops)

  Dir[File.expand_path("routes/**/*.rb", __dir__)].each { |f| require f }

  route do |r|
    r.hash_routes
  end
end
