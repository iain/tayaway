# typed: true
# frozen_string_literal: true

$stdout.sync = true

require_relative "config/environment"

use RequestLogger

# Start WebSocket listener for PostgreSQL NOTIFY (skip in test environment)
unless APP_ENV == "test"
  Websocket::Listener.start
end

if APP_ENV == "development"
  require_relative "lib/reloading"
  lock = Reloading.new_lock
  route_dir = APP_DIR.join("app/routes")
  Reloading.start_listener(lock:, loader: LOADER, code_dirs: [APP_DIR.join("app"), APP_DIR.join("lib")]) do
    Dir[route_dir.join("**/*.rb")].each { |f| load f }
  end
  use Reloading::Middleware, lock
  run ->(env) { App.app.call(env) }
else
  run App.freeze.app
end
