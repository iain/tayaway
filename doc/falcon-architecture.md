# Falcon backend architecture

Design target for the Tayaway backend server: lean on Falcon-host's supervisor as
the only top-level orchestrator, give every long-running concern its own
service, and replace ad-hoc `Thread.new` / `Concurrent::AtomicBoolean` /
`reactor.async {}` plumbing with structured concurrency.

This document describes the _target_ shape. The current code differs in
several places — see [What disappears](#what-disappears) for the deltas.

## One entry point: `falcon-host` everywhere

Dev and prod both run `bundle exec falcon-host backend/falcon.rb`. The systemd
unit becomes one line. Behaviour differs by env vars, not by command line.

```ruby
# backend/falcon.rb
#!/usr/bin/env -S falcon-host
require_relative "config/preload"   # eager-load Zeitwerk, warm DB.server_version, etc.
require "falcon/environment/rack"
require "async/container/supervisor/environment"

service "web" do
  include Tayaway::WebEnvironment           # extends Falcon::Environment::Rack
  count Integer(ENV.fetch("WEB_CONCURRENCY", Etc.nprocessors))
end

service "jobs" do
  include Tayaway::JobsEnvironment          # extends Async::Service::Managed::Environment
  count Integer(ENV.fetch("JOB_CONCURRENCY", 2))
end

service "scheduler" do
  include Tayaway::SchedulerEnvironment     # extends Async::Service::Managed::Environment
  count 1
end

service "supervisor" do
  include Async::Container::Supervisor::Environment
  monitors do
    [
      Async::Container::Supervisor::MemoryMonitor.new(
        interval: 30,
        total_size_limit: 512 * 1024 * 1024
      )
    ]
  end
end
```

`require_relative "config/preload"` runs in the host process before any
service forks, so Zeitwerk and DB warm-up are inherited by every worker. (The
per-service `preload` directive, if we ever need different preloads per
service, lives inside each `service` block as a method override.)

Each `service "..." do ... end` runs in its own forked container that the
supervisor manages — readiness handshake, restart-on-failure, graceful stop on
`SIGINT` / `SIGTERM`, fresh-fork-then-drain restart on `SIGHUP`, memory caps.
No bespoke lifecycle code in the app.

The `--threaded` workaround in `config/deploy/tayaway-falcon.service.erb` and
the corresponding comments in `app/websocket/listener.rb` and
`app/websocket/connection_manager.rb` ("production runs `falcon serve
--threaded`") all go away once Listener and Keepalive move onto the reactor
(see [Realtime](#realtime-per-worker-fibers-no-threads)). The original
readiness-handshake failure that motivated `--threaded` is documented in
`tayaway-falcon.service.erb` as kernel/user-specific; we should reproduce it
under `falcon-host` before assuming the new entry point fixes it. Worst case,
keep `count 1` on the `web` service (effectively single-process) until the
root cause is understood.

## Realtime: per-worker fibers, no threads

Each `web` worker is one process, one reactor, many fibers. PG `NOTIFY`
already fans out to every backend listening on the channel, so each worker can
subscribe independently and broadcast only to the websockets it owns. No Redis
bridge, no cross-worker IPC.

```ruby
# backend/config.ru — runs once per web worker, inside its reactor
require_relative "config/environment"

Async do |task|
  task.async(annotation: "realtime.listener")  { Tayaway::Realtime::Listener.run }
  task.async(annotation: "realtime.keepalive") { Tayaway::Realtime::Keepalive.run }
end

run Tayaway::App.freeze
```

```ruby
module Tayaway::Realtime
  module Listener
    CHANNEL = "tayaway_objects"

    def self.run(connections: ConnectionManager.instance)
      DB.synchronize do |raw|
        raw.query("LISTEN #{CHANNEL}")
        begin
          loop { raw.wait_for_notify { |_, _, payload| dispatch(payload, connections) } }
        ensure
          raw.query("UNLISTEN *")
        end
      end
    rescue => e
      Console.error(self, e)
      Async::Task.current.sleep(5) and retry
    end
  end
end
```

This replaces `Listener.start` / `Listener.stop` / `Concurrent::AtomicBoolean`
/ `Thread.join` / the dedicated `Sequel.connect`. `pg` has been
fiber-scheduler-aware since 1.3, so `wait_for_notify` yields the reactor
while the socket has no data — no extra `task.yield` needed. Fiber
cancellation on shutdown unwinds the loop, and the explicit `UNLISTEN *` in
the `ensure` clears the registration before Sequel returns the connection to
the pool (otherwise a later borrower of that connection would see stray
notifications).

Caveat: the pg/scheduler integration has rough edges — `config/database.rb`
already carries a workaround for `server_version` returning a String instead
of an Integer under the scheduler. Expect to find similar paper-cuts as
coverage expands.

`Keepalive.run` is just:

```ruby
loop { task.sleep(PING_INTERVAL); connections.ping_all(idle_timeout: IDLE_TIMEOUT) }
```

The mutex inside `ConnectionManager` becomes optional once everything in a
worker runs on one thread; keep it as cheap defensive value.

## Slow IO: `async-job`

Mailers and (future) outbound HTTP move to jobs. The "spawn on the parent
reactor" trick in `Mailers::Base.deliver_later` disappears.

`async-job`'s built-in `Async::Job::Generic` is bare — `id`, optional
`scheduled_at`, plus `serialize` and `call` to be implemented. Job arguments
aren't passed for free; we either build a thin `Tayaway::Jobs::Base` that
serializes/deserializes a kwargs payload, or pull in
[`async-job-adapter-active_job`](https://github.com/socketry/async-job-adapter-active_job)
to get ActiveJob's familiar API and test helpers at the cost of an
`activejob` + `activesupport` dependency. The doc assumes the
build-our-own path for now; revisit if the wrapper grows past one screen.

```ruby
class Tayaway::Jobs::Base < Async::Job::Generic
  def self.perform_later(**kwargs)
    QUEUE.call({ "class" => name, "kwargs" => kwargs })
  end

  def self.call(job)         # invoked by the dequeue side
    klass = Object.const_get(job.fetch("class"))
    klass.new(**job.fetch("kwargs").transform_keys(&:to_sym)).call
  end
end

class Tayaway::Jobs::SendLoginLink < Tayaway::Jobs::Base
  def initialize(user_id:, token:) = (@user_id, @token = user_id, token)
  def call = Mailers::LoginLink.deliver(user_id: @user_id, token: @token)
end

# call site
Tayaway::Jobs::SendLoginLink.perform_later(user_id: user.id, token: token)
```

`QUEUE` is the result of `Async::Job::Builder.build(delegate) { … }` — that's
where the processor and any middleware (retries, logging) live.

Processor by env:

- **production**: `async-job-processor-redis` is the only out-of-tree, durable
  processor today. Async-job ships `Inline`, `Aggregate`, and `Delayed`
  in-process backends, but no Postgres-backed processor — if we want to avoid
  Redis we'd have to write one (the LISTEN/NOTIFY plumbing we already have
  makes this tractable, but it is meaningful work, not a free lunch).
- **development**: same processor as production — parity catches bugs.
- **test**: `Async::Job::Processor::Inline`. Note this still runs jobs on a
  separate fiber via `Async::Idler`, not synchronously inside the enqueuing
  fiber — tests need to wait on the idler (or use
  `async-job-adapter-active_job`'s test mode if we go that route, which does
  give a true synchronous adapter and `assert_enqueued_with` /
  `enqueue_job` matchers).

Retries, scheduling, dead-lettering, and observability are built as middleware
in the `Builder` chain rather than reinvented per call site.

## Scheduled work

The `scheduler` service is a `count: 1` managed service with a single fiber
that `task.sleep`s until the next tick and enqueues into the same `async-job`
queue. It never _runs_ the work — it dispatches. Failure recovery and
parallelism are then the `jobs` service's problem, not the scheduler's.

## Fan-out inside a request

Already idiomatic in `app/routes/ws.rb`. Standardise the primitives:

- `Async::Barrier` — fan out, await all, propagate first error.
- `Async::Semaphore` — bound concurrency.
- `Async::Queue` / `Async::Notification` — fiber-to-fiber handoff.

Reach for these by name; don't wrap them in a helper unless three call sites
repeat the same pattern.

## Live reload in development

Use Falcon's own graceful restart, not in-process code reloading. A dev-only
`reloader` service watches `app/` and `lib/` with `listen` and sends `SIGHUP`
to the host process. `Async::Container::Controller#restart` (triggered by the
SIGHUP trap) forks a fresh container, waits for readiness, then drains the
old one — sub-second on this codebase. The frontend's existing websocket
reconnect handles the flap.

This deletes `lib/reloading.rb`, the read/write middleware lock, the manual
`Dir[].each { load }` of routes, and the `App.include ResultHandler`
re-include hack. Same pattern as production, fewer moving parts.

If we'd rather not pay the worker-restart cost on every save, keep the
Zeitwerk-based reloader but lift route loading and module re-inclusion into
Zeitwerk so the middleware is the only piece left.

## Testing

- Services are plain classes with `start` / `stop` / `run(instance, evaluator)`
  — instantiate and exercise without booting Falcon.
- `Listener` takes its DB connection and `ConnectionManager` via the
  constructor; specs feed it canned NOTIFY payloads through a stub PG.
- Jobs unit-test like any class; integration via `Processor::Inline`.
- The `Result` monad, `RequestContext`, `Auditable`, and Sequel
  `:fiber_concurrency` extension all carry through unchanged — they're already
  correct primitives for a fiber-per-request server.

## What disappears

- `Websocket::Listener` thread (with its `Concurrent::AtomicBoolean` running
  flag), `Websocket::Keepalive` thread (with its plain `@running` ivar),
  the dedicated `Sequel.connect` for the listener, and the `at_exit` /
  `Thread.join` shutdown choreography in `config.ru`.
- `Mailers::Base.deliver_later`'s `Async::Task.current?.reactor.async {}`
  reach-around.
- `--threaded` workaround in `config/deploy/tayaway-falcon.service.erb` and
  stale "production runs falcon serve --threaded" comments in `listener.rb`
  and `connection_manager.rb`.
- `DB.server_version` pre-warm + `DB.disconnect` dance in
  `config/database.rb` (moves into `preload.rb`).
- `lib/reloading.rb` and the route / module re-load hack (if we take the
  graceful-restart reload option above).

## What stays

Roda + `roda-websockets` (a thin shim over `async-websocket`, perfectly
idiomatic), Sequel + `:fiber_concurrency`, `RequestContext` / `Auditable`
Fiber-storage helpers, the `Result` chain shape, the `PoolSerializer`. The
architecture above is additive in spirit — same data flow, replaced
plumbing.

## Deployment

Today: Capistrano deploys to a single host. The post-publish hook does
`systemctl restart tayaway-falcon` — a hard restart with a few seconds of
nginx 502s before the new process binds. Switching the entry point to
`falcon-host` doesn't change this on its own, but it opens a path to an
actual graceful drain.

**Capistrano with falcon-host.** Replace `falcon serve --threaded …` in the
systemd unit with `falcon-host backend/falcon.rb`. Set `Type=notify` and
`ExecReload=/bin/kill -HUP $MAINPID`, and flip the deploy hook from
`falcon:restart` to `falcon:reload`. On SIGHUP,
`Async::Container::Controller#restart` forks a fresh container, waits for
`notify_ready!`, then drains the old one — a real graceful drain.

**The host-reload trap.** SIGHUP reloads the _workers_, not the host
process. Workers fork from the host and inherit its `$LOAD_PATH` / require
cache via copy-on-write — so a `systemctl reload` after Capistrano swaps the
`current` symlink re-forks workers against **stale code from the previous
release**. To pick up the new release the host has to re-exec, which means
`systemctl restart` (hard) — back where we started.

The pragmatic answer is to keep accepting the few-second `systemctl restart`
blip until we genuinely need zero-downtime. When we do, the simplest path is
two systemd units on different ports with nginx upstream failover and a
`falcon:flip` Capistrano task that brings the standby up, waits for ready,
then stops the active — roughly 30 lines of nginx config plus a rake task.
Socket-activated `Type=notify` with re-exec semantics is doable but fiddly;
not worth it before that.

## Kubernetes (when we get there)

The fiber-per-request web tier is already a great K8s citizen — stateless
workers, locally-routed WebSocket fan-out, clients reconnect on pod churn,
the object pool merges by `updatedAt`. Standard rolling deploys give true
zero-downtime for free, no symlink games. The pieces that _don't_ translate
cleanly:

- **Drop the supervisor service.** `MemoryMonitor` and restart-on-failure
  duplicate what kubelet does (OOMKilled, livenessProbe, `restartPolicy`).
  On K8s the supervisor entry in `falcon.rb` becomes dead weight — let the
  orchestrator own process lifecycle.
- **One process per container, not forked workers.** Set `WEB_CONCURRENCY=1`
  in the manifest and scale via `replicas: N`. `count` in `falcon.rb`
  effectively becomes a 1 in this environment.
- **Scheduler needs leader election or its own Deployment.** `count 1`
  inside `falcon-host` only protects against multiple schedulers within a
  single host; across N pods, every tick fires N times. Either give the
  scheduler its own `Deployment` with `replicas: 1` (simple, sufficient),
  or use a PG advisory lock (`pg_try_advisory_lock`) so any replica can
  become the active scheduler.
- **Watch the `LISTEN` connection budget.** Per-worker subscription is fine
  at small scale; at horizontal scale `pods × WEB_CONCURRENCY` listeners
  (plus query connections) starts to crowd PG's `max_connections`. Two
  mitigations when it bites: consolidate to one listener per pod that fans
  out to local workers via `Async::Notification`, or front PG with PgBouncer
  in transaction-mode pooling and pin the listener connections outside the
  pool.
- **If we build a Postgres job processor**, it must use
  `SELECT … FOR UPDATE SKIP LOCKED` to be safe across replicas. Redis-backed
  (`async-job-processor-redis`) is multi-replica-safe out of the box.

## Migration sequence

Each step ships on its own, but steps 1 and 2 are coupled in practice — see
the note on step 1.

1. Flip to `falcon-host` with a `web` service only. **Don't drop `--threaded`
   yet** — the OS-thread Listener/Keepalive in `config.ru` need the
   single-process model that `--threaded` provides. (`falcon-host` defaults
   to the same forked-container model `falcon serve` uses without
   `--threaded`, which is also where the original readiness-handshake bug
   lives.) Verify the readiness handshake under `falcon-host` first; if it
   reproduces, keep `count 1` on the `web` service until step 2 retires the
   threads.
2. Move `Listener` and `Keepalive` into per-worker Async tasks. At this point
   `--threaded` and the dedicated `Sequel.connect` go away together.
3. Introduce `async-job` with the inline processor and migrate mailers.
4. Add `jobs` and `scheduler` services and switch to a real processor (Redis
   today, or roll a Postgres processor on top of LISTEN/NOTIFY).
5. Replace the in-process reloader with graceful-restart-on-file-change.
