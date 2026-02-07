# typed: true
# frozen_string_literal: true

require "sequel"

# Lazy database connection - defers connection until first use
# This is required for Falcon which forks after loading config.ru
DB = Sequel.connect(ENV.fetch("DATABASE_URL"), preconnect: false, test: false)

DB.extension :pg_json
DB.extension :pg_array
