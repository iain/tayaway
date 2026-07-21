# frozen_string_literal: true

# Connection for the admin dashboard's read queries. In production
# ADMIN_DATABASE_URL points at a read-only Postgres role (doc/admin.md), so
# a bug in a panel query physically cannot write; when unset (dev/test) it
# falls back to the main DB connection — which also keeps DatabaseCleaner's
# transaction strategy intact in specs.
module AdminDb
  class << self
    def connection
      if APP_CONFIG.admin_database_url
        @connection ||= connect
      else
        DB
      end
    end

    private

    # Mirrors config/database.rb: the same pg type extensions (jsonb columns
    # must come back wrapped, not as raw strings the templates would
    # double-encode) and the same per-connection statement timeout / UTC
    # session. Only the pool sizing differs — one worker, one operator.
    def connect
      db = Sequel.connect(
        APP_CONFIG.admin_database_url,
        # Stay out of the global Sequel::DATABASES registry: nothing resolves
        # databases through it here, and registering a second one breaks
        # DatabaseCleaner's "exactly one active database" check in specs.
        keep_reference: false,
        preconnect: false,
        test: false,
        max_connections: 4,
        pool_timeout: 5,
        connect_timeout: 5,
        after_connect: proc { |conn| conn.exec("SET statement_timeout = '30s'; SET TIME ZONE 'UTC'") }
      )
      db.extension :pg_json
      db.extension :pg_array
      db.extension :pg_inet
      db
    end
  end
end
