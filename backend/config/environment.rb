# typed: true
# frozen_string_literal: true

require "bundler/setup"
Bundler.require(:default, ENV.fetch("RACK_ENV", "development"))

require "dotenv/load" unless ENV["RACK_ENV"] == "production"

require_relative "database"

Dir[File.expand_path("../app/models/**/*.rb", __dir__)].each { |f| require f }

require_relative "../app/app"
