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
# trigger a controller restart on change. Async::Container::Controller
# treats a SIGHUP as the restart signal, but it has a sharp edge —
# a second SIGHUP arriving while the previous restart is still
# draining workers re-raises Async::Container::Restart through the
# in-progress IO.select, escapes the controller's rescue, and tears
# the host down. Saves bunched together (rebases, search-and-replace
# across files, fast-paced editing) hit it routinely.
#
# So we serialise saves around the actual restart cycle: a save while
# a restart is running flips a `pending` bit, and a `prepend` on the
# controller fires the queued HUP from the `ensure` of `restart` once
# it has actually returned. No time-based cooldown — the gate opens
# on the real completion event. No reactor either; the controller
# runs on plain IO.select before any reactor exists in the host, and
# Listen's callback runs on its own thread, so a Mutex is the
# correct primitive to synchronise the two.
if ENV.fetch("RACK_ENV", "development") == "development"
  require "listen"
  require "async/container/controller"

  module DevReloader
    @mutex = Mutex.new
    @restart_in_progress = false
    @save_pending = false

    class << self
      def on_save
        fire = @mutex.synchronize do
          if @restart_in_progress
            @save_pending = true
            false
          else
            @restart_in_progress = true
            true
          end
        end
        Process.kill("HUP", Process.pid) if fire
      end

      def on_restart_completed
        fire = @mutex.synchronize do
          @restart_in_progress = false
          if @save_pending
            @save_pending = false
            @restart_in_progress = true
            true
          else
            false
          end
        end
        Process.kill("HUP", Process.pid) if fire
      end
    end
  end

  module DevReloaderRestartHook
    def restart(...)
      super
    ensure
      DevReloader.on_restart_completed
    end
  end
  Async::Container::Controller.prepend(DevReloaderRestartHook)

  reloader = Listen.to(
    File.expand_path("app", __dir__),
    File.expand_path("lib", __dir__),
    wait_for_delay: 0.5
  ) { DevReloader.on_save }
  reloader.start
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
