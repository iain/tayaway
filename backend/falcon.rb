# frozen_string_literal: true

# falcon-host entry point. Loaded by `bin/falcon-host falcon.rb`.
#
# Each worker is a forked process that loads its own initialisation —
# Zeitwerk, mailer config, DB.server_version pre-cache — after fork.
# Pre-loading from the host would amortise that work via copy-on-write
# but is unsafe with libpq: any DB connect in the host poisons libpq
# state for forked children and segfaults their first Sequel.connect.

# falcon-host's notify pipe and Ruby's resolv.rb both poke at the
# experimental IO::Buffer API, which warns on every load. We don't have
# a way to upgrade those callers; silence the noise here.
Warning[:experimental] = false

require "falcon/environment/rack"
require "async/service/managed/service"
require "async/service/managed/environment"

# Service class that boots the durable Postgres-backed job worker. The
# `run` hook fires inside each forked container, so we lazy-load the app
# environment here — by the time it executes, we're past the fork that
# made libpq state safe.
class JobsServiceContainer < Async::Service::Managed::Service
  def run(_instance, _evaluator)
    # The jobs worker only needs a couple of pooled connections: one for
    # claim/execute/delete and one permanently parked on LISTEN inside
    # `wait_for_signal`. A pool of 4 leaves headroom for a transient
    # second query during retry-bookkeeping. Web workers stay on the
    # database.rb default (16) — see the connection-budget note there
    # for how the LISTEN hold interacts with `count` and PG's
    # `max_connections`.
    ENV["DATABASE_POOL_SIZE"] ||= "4"
    require_relative "config/environment"
    Async do
      Jobs::Worker.run
    end
  end
end

module JobsServiceEnvironment
  include Async::Service::Managed::Environment

  def name
    "jobs"
  end

  def service_class
    JobsServiceContainer
  end
end

# Dev-only code reload: watch app/ and lib/ in the host process and
# SIGHUP ourselves on change. Async::Container::Controller turns the
# SIGHUP into a fresh-fork-then-drain restart of every worker. Running
# the watcher in the host (rather than a forked service) keeps the
# Listen gem's fsevent_w / inotify subprocess as a direct child of the
# host, so it terminates cleanly when the host exits — no orphaned
# subprocesses holding the listen socket between dev-server runs.
#
# Two-stage debounce:
#   1. Listen's `wait_for_delay` collapses the fsevent burst macOS
#      produces for a single save into one callback.
#   2. A dedicated worker thread serialises those callbacks behind a
#      cooldown sleep — async-container can't safely receive a second
#      Async::Container::Restart while it's still draining workers
#      from the first. The Thread#raise into a mid-restart IO.select
#      escapes the controller's rescue and tears the host down.
#
# The cooldown has to outlast the longest graceful-shutdown a worker
# can take. Falcon waits for in-flight WebSockets to close before
# exiting, so a connected dev browser pushes us into async-container's
# ~10s SIGKILL fallback. 15s leaves headroom for that plus the
# fork+startup of the new workers. Saves arriving inside the cooldown
# flip `reload_pending` back on; the next iteration of the loop picks
# them up and fires one follow-up HUP — no save is lost.
if ENV.fetch("RACK_ENV", "development") == "development"
  require "listen"
  reload_cooldown = 15
  reload_mutex = Mutex.new
  reload_signal = ConditionVariable.new
  reload_pending = false

  reloader = Listen.to(
    File.expand_path("app", __dir__),
    File.expand_path("lib", __dir__),
    wait_for_delay: 0.5
  ) do
    reload_mutex.synchronize do
      reload_pending = true
      reload_signal.signal
    end
  end
  reloader.start

  Thread.new do
    loop do
      reload_mutex.synchronize do
        reload_signal.wait(reload_mutex) until reload_pending
        reload_pending = false
      end
      Process.kill("HUP", Process.pid)
      sleep reload_cooldown
    end
  end
end

service "web" do
  include Falcon::Environment::Rack

  # Defaults to one container until the production readiness handshake
  # is verified under falcon-host's forked-container model — see
  # doc/falcon-architecture.md migration step 1 — but exposed as
  # WEB_CONCURRENCY (matching JOB_CONCURRENCY below) so the cap can be
  # lifted from deployment without a code change. `.to_i` (rather than
  # Integer(...)) because the service block runs inside an
  # Async::Service::Environment::Builder (BasicObject) which can't see
  # Kernel#Integer.
  count ENV.fetch("WEB_CONCURRENCY", "1").to_i

  url ENV.fetch("FALCON_URL", "http://localhost:9292")

  # Falcon::Environment::Rack defaults to a Unix-socket proxy endpoint
  # because falcon-host's canonical layout is many services behind a
  # TLS-terminating proxy service. We have nginx in front in prod and
  # Vite in front in dev, so bind directly to the TCP url instead.
  endpoint { Async::HTTP::Endpoint.parse(url) }
end

service "jobs" do
  include JobsServiceEnvironment

  # ENV.fetch.to_i instead of Integer(...) — the falcon-host service block
  # is evaluated inside an Async::Service::Environment::Builder, which
  # subclasses BasicObject and so can't see Kernel#Integer.
  count ENV.fetch("JOB_CONCURRENCY", "1").to_i
end
