# frozen_string_literal: true

# The admin store is SQLite, outside DatabaseCleaner's reach — wipe it
# per example instead. Deleting from two empty tables is microseconds.
RSpec.configure do |config|
  config.before do
    Admin::State.db[:admin_sessions].delete
    Admin::State.db[:admin_credentials].delete
  end
end
