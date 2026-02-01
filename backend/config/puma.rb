# typed: false
# frozen_string_literal: true

require "dotenv"

rack_env = ENV.fetch("RACK_ENV", "development")
Dotenv.overload(".env.#{rack_env}")

port ENV.fetch("PORT", 9292)
environment rack_env
