# typed: true
# frozen_string_literal: true

require "sequel"

# Lazy database connection - defers connection until first use
# This is required for Falcon which forks after loading config.ru
DB = Sequel.connect(ENV.fetch("DATABASE_URL"), preconnect: false, test: false)

DB.extension :pg_json
DB.extension :pg_array

# Pre-cache the server version before Falcon forks workers.
# Under Falcon's fiber scheduler, the pg gem may return the version as a
# String instead of Integer, which breaks Sequel's generated SQL methods
# that compare `server_version >= 80400`. By resolving it here (outside the
# fiber scheduler), we get the correct Integer and then disconnect so forked
# workers create their own connections.
DB.server_version
DB.disconnect
