# typed: true
# frozen_string_literal: true

$stdout.sync = true

require_relative "config/environment"

use Rack::Attack
use RequestLogger

# Spawn the WebSocket Listener and Keepalive on the worker's reactor.
# Under falcon-host, config.ru is loaded inside an Async task during
# worker startup, so Task.current? is non-nil and these fibers run for
# the lifetime of the worker. Outside a reactor (e.g. `rackup` directly,
# or a tool that loads config.ru just to introspect routes) we skip the
# spawn rather than crash.
unless APP_CONFIG.test?
  parent = Async::Task.current?
  if parent
    parent.async(annotation: "websocket.listener")  { Websocket::Listener.run }
    parent.async(annotation: "websocket.keepalive") { Websocket::Keepalive.run }
  else
    APP_LOGGER.warn { "[config.ru] No active reactor; Listener/Keepalive not started" }
  end
end

# Code reload in development is a graceful restart of the whole
# falcon-host container, driven by the dev-only `reloader` service in
# falcon.rb that watches app/ and lib/ and sends SIGHUP. Same model as
# production, fewer moving parts than an in-process Zeitwerk reload.
run App.freeze.app
