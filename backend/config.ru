# typed: true
# frozen_string_literal: true

$stdout.sync = true

require_relative "config/environment"

use Rack::Attack
use RequestLogger

# Start WebSocket listener for PostgreSQL NOTIFY (skip in test environment)
unless APP_ENV == "test"
  Websocket::Listener.start
  Websocket::Keepalive.start
end

if APP_ENV == "development"
  require_relative "lib/reloading"
  lock = Reloading.new_lock
  route_dir = APP_DIR.join("app/routes")
  Reloading.start_listener(lock:, loader: LOADER, code_dirs: [APP_DIR.join("app"), APP_DIR.join("lib")]) do
    Dir[route_dir.join("**/*.rb")].each { |f| load f }
    # Re-include ResultHandler so App#handle_result uses the freshly-loaded module
    # with up-to-date Sorbet sig references (avoids stale-class type errors after reload).
    App.include ResultHandler
  end
  use Reloading::Middleware, lock
  run ->(env) { App.app.call(env) }
else
  run App.freeze.app
end
