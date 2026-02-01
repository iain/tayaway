# typed: true
# frozen_string_literal: true

require_relative "config/environment"

use Rack::CommonLogger

if APP_ENV == "development"
  require_relative "lib/reloading"
  lock = Reloading.new_lock
  Reloading.start_listener(lock:, loader: LOADER, code_dirs: [APP_DIR.join("app/models")])
  use Reloading::Middleware, lock
  run ->(env) { App.app.call(env) }
else
  run App.freeze.app
end
