# frozen_string_literal: true

# Refuses to run the suite against anything but the dedicated test database.
# `ENV["MISE_ENV"] = "test"` in spec_helper can't undo a DATABASE_URL that
# mise already loaded into the shell from .env.development, and the
# before(:suite) truncation would then wipe that database.
module TestDatabaseGuard
  EXPECTED_DATABASE = "tayaway_test"

  class << self
    def test_database?(database_name)
      database_name == EXPECTED_DATABASE
    end

    def enforce!(database_name)
      unless test_database?(database_name)
        abort <<~MSG
          RSpec is connected to #{database_name.inspect}, not #{EXPECTED_DATABASE.inspect} — aborting
          before DatabaseCleaner truncates it.

          DATABASE_URL was most likely inherited from mise's development env
          (bare `bundle exec rspec`). Run specs through the mise task instead:

            mise run '//backend:test' [spec/path/to/spec.rb]
        MSG
      end
    end
  end
end
