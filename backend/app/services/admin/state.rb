# frozen_string_literal: true

module Admin
  # The admin site's own SQLite store (credentials + sessions). Connects
  # lazily so the main app's processes never open (or create) the file —
  # only the admin process and specs touch it. Migrations run on first
  # connect: the store is tiny and single-operator, so boot-time migration
  # needs no deploy wiring.
  module State
    class << self
      def db
        @_db ||= connect
      end

      private

      def connect
        path = APP_CONFIG.admin_state_path ||
               APP_DIR.join("tmp", "admin_state.#{APP_CONFIG.app_env}.db")
        FileUtils.mkdir_p(File.dirname(path))

        # One connection: a single operator never needs write concurrency,
        # and SQLite is happiest without it. WAL keeps a reader (a dashboard
        # request) from blocking the login write path.
        db = Sequel.sqlite(path.to_s, max_connections: 1)
        db.run("PRAGMA journal_mode = WAL")
        db.run("PRAGMA busy_timeout = 5000")

        Sequel.extension :migration
        Sequel::Migrator.run(db, APP_DIR.join("db", "admin_migrations").to_s)
        db
      end
    end
  end
end
