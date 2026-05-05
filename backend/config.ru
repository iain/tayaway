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
end

# Code reload in development is a graceful restart of the whole
# falcon-host container, driven by the dev-only `reloader` service in
# falcon.rb that watches app/ and lib/ and sends SIGHUP. Same model as
# production, fewer moving parts than an in-process Zeitwerk reload.
run App.freeze.app
