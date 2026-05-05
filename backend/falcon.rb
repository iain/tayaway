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
if ENV.fetch("RACK_ENV", "development") == "development"
  require "listen"
  reloader = Listen.to(File.expand_path("app", __dir__), File.expand_path("lib", __dir__)) do
    Process.kill("HUP", Process.pid)
  end
  reloader.start
end

service "web" do
  include Falcon::Environment::Rack

  # Pinned to one container until the production readiness handshake
  # is verified under falcon-host's forked-container model. See
  # doc/falcon-architecture.md migration step 1.
  count 1

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
