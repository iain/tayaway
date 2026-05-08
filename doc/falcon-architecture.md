# Falcon backend architecture

The backend is one falcon-host process per node. It runs a small set of
services — today a `web` service and a `jobs` service — each as a forked
container of worker processes managed by `async-container`. Inside each
worker, everything that needs to run concurrently runs as a fiber on a
single reactor. There are no application-managed threads.

The principles below are what this shape exists to enforce. Reach for them
before reaching for Sequel pools, OS threads, or another service.

## One process, one reactor, many fibers

A worker is a forked process with one Ruby thread, one Async reactor, and
as many fibers as it needs. Concurrency between requests, background
listeners, broadcasts, and outbound IO is fiber concurrency on that
reactor.

This is what makes most of the codebase look the way it does:

- **Sequel runs with `:fiber_concurrency`** so connections are keyed by
  fiber, not thread. Without it, two concurrent request fibers would share
  a connection and corrupt each other's results.
- **The mutex inside `ConnectionManager` is defensive, not load-bearing.**
  Fiber boundaries already serialise access; the mutex is there in case an
  OS thread ever sneaks in.
- **Background work goes on the reactor**, not on a `Thread.new`. The
  WebSocket Listener and Keepalive are fibers spawned from `config.ru`
  during worker boot. The job worker is a fiber inside its own service
  container.

The only thread-aware code that should appear in the app is code that
deliberately bridges to libraries that themselves spawn threads. In
practice that's nothing today.

## Entry point

`bin/falcon-host falcon.rb` is the only command. Dev and prod run the same
binary; the systemd unit is one `ExecStart` line. Per-environment behaviour
comes from env vars (`RACK_ENV`, `WEB_CONCURRENCY`, `JOB_CONCURRENCY`,
`DATABASE_URL`, `FALCON_URL`).

Inside `falcon.rb`:

- `service "web"` is a `Falcon::Environment::Rack` service. We bind it
  directly to a TCP url instead of falcon-host's default Unix-socket proxy
  layout — there is exactly one service serving HTTP, with nginx (prod) or
  Vite (dev) in front.
- `service "jobs"` is a managed service whose `run` hook starts
  `Jobs::Worker.run` inside an `Async {}` block.
- In development only, the host process runs a `Listen` watcher over
  `app/` and `lib/` and sends itself `SIGHUP` on change. `falcon-host`'s
  controller turns SIGHUP into a fresh-fork-then-drain restart of every
  worker. The watcher lives in the host (not a forked service) so its
  fsevent/inotify subprocess stays a direct child and exits cleanly.

There is no scheduler service and no supervisor service. If we add either
later, they slot in as additional `service "..."` blocks.

### libpq + fork

`falcon.rb` itself does not require `config/environment`. Each forked
worker loads it lazily — config.ru for `web`, `JobsServiceContainer#run`
for `jobs`. This is deliberate: any libpq connection opened in the host
process poisons libpq state for forked children and segfaults their first
`Sequel.connect`. Pre-loading via copy-on-write would be cheaper but is
not safe with libpq.

`config/database.rb` calls `DB.server_version` and immediately
`DB.disconnect` to pre-cache the version under a non-fiber-scheduler
context (the pg gem returns a String instead of an Integer under the
fiber scheduler, which breaks Sequel's generated SQL). The disconnect
is what lets each forked worker start clean.

## Realtime

Each web worker subscribes to PG `NOTIFY` independently and broadcasts
only to the WebSockets it owns. There is no Redis bridge and no
cross-worker IPC — Postgres' fan-out across listening backends is the
fan-out.

The listener fiber parks on a single pooled connection via Sequel's
`DB.listen(channel, loop: true)`, which handles `LISTEN`/`UNLISTEN`
and properly escapes the channel identifier. Concurrency is bounded
at two layers, both via `Async::Semaphore`: each incoming notification
is dispatched on its own child fiber so the listener returns to
`wait_for_notify` immediately, and inside `broadcast_to_workspace` the
per-recipient writes fan out under a second semaphore. A slow TCP
receiver can only stall its own write fiber — clients in other
workspaces and other clients in the same workspace deliver in parallel.
Both caps stay well below the Sequel pool's free slots so broadcast
fibers don't crowd request connections.

The Keepalive fiber is the same shape: a `loop { task.sleep; tick }` that
prunes idle WebSockets.

## Jobs

The job system is in `lib/jobs/`. Three pieces:

- `Jobs::Base` — subclass and implement `call(**kwargs)`. Payloads are
  flat scalar kwargs; if you need structured input, persist an ID and
  look it up in `call`. Each invocation runs on a fresh instance.
- `Jobs::Queue.enqueue` — inserts into `async_jobs` and `pg_notify`s the
  worker. In `test`, jobs run inline so specs don't need a worker loop.
- `Jobs::Worker` — fiber on the jobs service's reactor. Holds one
  `LISTEN` parked on a pooled connection, claims work via
  `FOR UPDATE SKIP LOCKED`, runs it, and on failure schedules a retry
  with exponential backoff or dead-letters past `MAX_ATTEMPTS`.

The durability invariants worth knowing:

- **Claims are durable, including across crashes.** If a worker dies
  hard (SIGKILL, OOM, container eviction) holding `locked_at`, no one
  else can pick the row up because the runnable index excludes locked
  rows. Each worker tick therefore starts with a `reclaim_stale` sweep:
  rows whose `locked_at` is older than `RECLAIM_AFTER` (5 min,
  comfortably above the 30 s `statement_timeout`) are routed through
  the same retry path a normal failure takes. SKIP LOCKED in the sweep
  ensures we never steal a row from a still-running peer.
- **Time anchors to the database clock.** `claim_next` and the retry
  scheduler compare and write `clock_timestamp()`, never `Time.now`.
  Mixing the two would drift on clock skew and, in tests wrapped by
  database_cleaner, would compare against the outer transaction's
  `CURRENT_TIMESTAMP` and miss freshly-inserted rows.
- **Only `Jobs::Base` subclasses execute.** `execute` checks the class
  before calling `.run`, so a row with a foreign class name fails fast
  instead of resolving to whatever `Object.const_get` returns.

Mailers are the only job consumer today. Each mailer module owns its
delivery job as an inner class — `Mailers::LoginLink::DeliveryJob`,
`Mailers::WorkspaceInvite::DeliveryJob`, etc. The mailer's `send_email`
enqueues; the worker fires `perform_delivery` to build the message and
hand it to `Mailers::Base.deliver`. SMTP credentials are read at send
time, not at boot, so a missing env var only raises when an email is
actually sent.

## Connection budget

Every fiber parked on `LISTEN` holds one pool connection for the lifetime
of the process: one in each web worker (Listener) and one in each jobs
worker (`Jobs::Worker`). Effective request-pool size is therefore
`DATABASE_POOL_SIZE - 1`.

Web workers run with the default pool (16). The jobs container sets
`DATABASE_POOL_SIZE=4` before requiring `config/environment`: the worker
needs at most one query in flight plus the parked LISTEN, with headroom
for a transient retry-bookkeeping query.

The cap that matters at the system level is
`pods × workers × DATABASE_POOL_SIZE` against PG's `max_connections`. If
we ever scale `WEB_CONCURRENCY` and pod count together, the per-worker
LISTEN starts to crowd out request connections and we'll need either a
single LISTEN per pod that fans out to local workers via
`Async::Notification`, or PgBouncer in transaction-mode pooling with
listener connections pinned outside the pool.

## Code reload in development

Reload is a graceful container restart, not in-process file reloading.
The `Listen` watcher in the host fires `SIGHUP`,
`Async::Container::Controller#restart` forks a fresh container, waits
for readiness, then drains the old one. Same model as production,
sub-second on this codebase, frontend's WebSocket reconnect handles the
flap.

This is why there is no Zeitwerk reloader, no route re-`load` loop, and
no read/write middleware lock. Each worker is single-shot from boot to
SIGHUP.

## Deployment

`config/deploy/tayaway-falcon.service.erb` is a systemd unit that
`ExecStart`s `bin/falcon-host falcon.rb`. `Restart=on-failure` covers
crashes; `ExecReload=/bin/kill -HUP $MAINPID` is wired for graceful
worker reloads. Capistrano's post-publish step today is a
`systemctl restart`, so deploys take the few-second 502 blip while the
new process binds.

Genuine zero-downtime requires the host to re-exec against the new
release (SIGHUP only re-forks workers, which inherit the host's stale
require cache via copy-on-write — a `systemctl reload` after the symlink
swap would re-fork against the _previous_ release). When we need it,
the simplest path is two systemd units on different ports with nginx
upstream failover and a `falcon:flip` rake task.

## Testing

- `Listener`, `Keepalive`, and `Jobs::Worker` are plain modules with
  `run`/`tick`/`drain` entry points. Specs call those directly and feed
  them canned input — no falcon-host, no fork.
- Jobs unit-test like any class. `Queue.enqueue` runs them inline in
  test, so specs assert on side-effects without spinning up a worker.
- The fiber-scheduler-aware bits (`pg`, Sequel `:fiber_concurrency`)
  carry through unchanged — they are correct primitives for a
  fiber-per-request server.

## Where this would change

The current shape is built for one host. A few things shift if we move
to multiple replicas:

- **Per-pod LISTEN consolidation** if the connection budget gets tight
  (see above).
- **A Postgres-backed scheduler with leader election** (e.g.
  `pg_try_advisory_lock`) or a separate `replicas: 1` deployment, so a
  scheduled tick fires once across the cluster rather than N times.
- **Drop `Restart=on-failure` reliance** in favour of the orchestrator's
  liveness handling.

None of those need code today. The point of the architecture above is
that they are local changes when the time comes, not rewrites.
