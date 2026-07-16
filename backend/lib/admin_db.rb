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
        @connection ||= Sequel.connect(APP_CONFIG.admin_database_url, max_connections: 4)
      else
        DB
      end
    end
  end
end
