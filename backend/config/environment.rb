# typed: true
# frozen_string_literal: true

APP_ENV = ENV.fetch("RACK_ENV", "development")
APP_DIR = Pathname(File.expand_path("..", __dir__))

require "bundler/setup"
Bundler.require(:default, APP_ENV)

Dotenv.overload("#{APP_DIR}/.env.#{APP_ENV}") unless APP_ENV == "production"

require_relative "database"

LOADER = Zeitwerk::Loader.new
LOADER.inflector.inflect("uuid" => "UUID")
LOADER.push_dir(File.expand_path("../lib", __dir__))
LOADER.push_dir(File.expand_path("../app/models", __dir__))
LOADER.push_dir(File.expand_path("../app/serializers", __dir__))
LOADER.push_dir(File.expand_path("../app/services", __dir__))
LOADER.enable_reloading if APP_ENV == "development"
LOADER.setup
LOADER.eager_load if APP_ENV == "production"

require_relative "../app/app"
