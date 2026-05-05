# frozen_string_literal: true

# falcon-host entry point. Loaded by `bin/falcon-host falcon.rb`.
#
# Each worker is a forked process that loads its own initialisation —
# Zeitwerk, mailer config, DB.server_version pre-cache — after fork.
# Pre-loading from the host would amortise that work via copy-on-write
# but is unsafe with libpq: any DB connect in the host poisons libpq
# state for forked children and segfaults their first Sequel.connect.

require "falcon/environment/rack"
require "async/service/managed/service"
require "async/service/managed/environment"

# Service class that boots the durable Postgres-backed job worker. The
# `run` hook fires inside each forked container, so we lazy-load the app
# environment here — by the time it executes, we're past the fork that
# made libpq state safe.
class JobsServiceContainer < Async::Service::Managed::Service
  def run(_instance, _evaluator)
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

# Dev-only file-watcher service. On change in app/ or lib/, sends SIGHUP
# to the falcon-host process, which Async::Container::Controller turns
# into a fresh-fork-then-drain restart of every service. That's how we
# pick up code changes — no in-process Zeitwerk reload, no middleware
# read/write lock, no manual route reload.
class ReloaderServiceContainer < Async::Service::Managed::Service
  def run(_instance, _evaluator)
    require "listen"
    backend_dir = File.expand_path(__dir__)
    listener = Listen.to(File.join(backend_dir, "app"), File.join(backend_dir, "lib")) do
      Process.kill("HUP", Process.ppid)
    end
    listener.start
    Async { Async::Task.current.sleep }
  end
end

module ReloaderServiceEnvironment
  include Async::Service::Managed::Environment

  def name
    "reloader"
  end

  def service_class
    ReloaderServiceContainer
  end
end

service "web" do
  include Falcon::Environment::Rack

  # Pinned to one container until the production readiness handshake
  # is verified under falcon-host's forked-container model. See
  # doc/falcon-architecture.md migration step 1.
  count 1

  url ENV.fetch("FALCON_URL", "http://localhost:9292")
end

service "jobs" do
  include JobsServiceEnvironment

  # ENV.fetch.to_i instead of Integer(...) — the falcon-host service block
  # is evaluated inside an Async::Service::Environment::Builder, which
  # subclasses BasicObject and so can't see Kernel#Integer.
  count ENV.fetch("JOB_CONCURRENCY", "1").to_i
end

if ENV.fetch("RACK_ENV", "development") == "development"
  service "reloader" do
    include ReloaderServiceEnvironment

    count 1
  end
end
