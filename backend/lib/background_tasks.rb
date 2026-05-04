# frozen_string_literal: true

# Rack middleware that boots the WebSocket Listener and Keepalive tasks on
# the first request.
#
# Both tasks need to live on Falcon's reactor (so they share a fiber scheduler
# with request handlers and the ConnectionManager singleton can be lock-free),
# but config.ru loads before the reactor exists. The first request is the
# earliest point at which we're guaranteed to be inside it, so we lazily start
# the tasks here.
class BackgroundTasks
  def initialize(app)
    @app = app
    @started = false
  end

  def call(env)
    start_once
    @app.call(env)
  end

  private

  def start_once
    return if @started

    # Set @started before spawning so a concurrent fiber can't double-start.
    # Safe under the cooperative scheduler: spawning a child task doesn't
    # yield, so no other fiber observes @started == false in between.
    @started = true
    Websocket::Listener.start
    Websocket::Keepalive.start
  end
end
