require "bundler/setup"
Bundler.require(:default, ENV.fetch("RACK_ENV", "development"))

require "dotenv/load" unless ENV["RACK_ENV"] == "production"

require_relative "database"
require_relative "../app/app"
