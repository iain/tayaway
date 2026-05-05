# typed: true
# frozen_string_literal: true

$stdout.sync = true

require_relative "config/environment"

use Rack::Attack
use RequestLogger

# Spawn the WebSocket Listener and Keepalive on the worker's reactor.
# config.ru is loaded inside an Async task during Falcon's worker startup,
# so Async::Task.current is non-nil here and these fibers run alongside
# request-handling fibers for the lifetime of the worker. They get
# cancelled — and their LISTEN/UNLISTEN dance unwinds — when Falcon stops
# the worker.
unless APP_ENV == "test"
  parent = Async::Task.current
  parent.async(annotation: "websocket.listener")  { Websocket::Listener.run }
  parent.async(annotation: "websocket.keepalive") { Websocket::Keepalive.run }
  parent.async(annotation: "jobs.worker")         { Jobs::Worker.run }
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
