# Backend Code Review

Full audit of the backend codebase across 8 dimensions: correctness, reliability, security,
observability, operability, performance, testability, and maintainability.

---

## Critical

- [ ] **[Reliability] No global error handler for unhandled exceptions**
      `app/app.rb` — No `error_handler` plugin. Unhandled exceptions (e.g. `PG::ConnectionBad`,
      `NoMethodError`) bubble up to Rack and return a raw 500 with no JSON body. The frontend
      expects `{ error: "..." }` responses.
      **Fix:** Add Roda's `error_handler` plugin to catch all `StandardError` and return
      `{ error: "Internal server error" }` with status 500, plus log the exception with backtrace.

- [ ] **[Operability] No graceful shutdown or zero-downtime restart**
      `lib/capistrano/tasks/falcon.rake:6`, `config/deploy/tayaway-falcon.service:16` —
      Deploy issues `systemctl restart`, which drops all in-flight HTTP requests and severs all
      WebSocket connections. No `ExecReload` directive in the systemd unit.
      **Fix:** Use Falcon's graceful restart (SIGUSR1) or add `ExecReload` to the systemd unit
      and change Capistrano to `systemctl reload`.

- [ ] **[Testability] Settlements::Create balance/transfer algorithm is untested**
      `app/services/settlements/create.rb:146-240` — `compute_balances` (pro-rata splitting)
      and `minimize_transfers` (greedy debt simplification) contain complex floating-point
      arithmetic with rounding (`.round(2)`, threshold `0.005`). Zero test coverage.
      **Fix:** Add tests covering equal splits, partial date overlaps, three-party debt
      simplification, and floating-point edge cases near the 0.005 threshold.

- [ ] **[Testability] 9 services have no tests at all**
      Missing specs for: `Expenses::Update`, `Expenses::Delete`, `Settlements::Create`,
      `Settlements::Delete`, `Settlements::MarkPaid`, `Invites::Remind`, `TaskLists::DeleteItem`,
      `Sync::WorkspaceSync`, `Broadcaster`.
      **Fix:** Prioritize `Settlements::Create`, `Expenses::Update/Delete` (authorization +
      settled-expense guard), and `Invites::Remind` (rate-limiting logic).

---

## Major

### Correctness

- [ ] **[Correctness] DatePolls::Close auto-RSVP can abort on unique constraint violation**
      `app/services/date_polls/close.rb:89-93` — Auto-RSVPs "yes" voters via raw INSERT. If a
      user already has an RSVP, `UniqueConstraintViolation` rolls back the entire transaction.
      **Fix:** Use `INSERT ... ON CONFLICT (event_id, user_id) DO NOTHING` or check for existing RSVPs.

- [ ] **[Correctness/Security] Invite management endpoints lack admin/owner authorization**
      `app/routes/invites.rb:60,75,94,109` — POST (create), DELETE (cancel), and POST remind
      only check `member_of_workspace?`, but CLAUDE.md documents these as admin/owner only.
      Any workspace member can create, cancel, and resend invites.
      **Fix:** Add `require_admin_or_owner!` checks for create, delete, and remind endpoints.

- [ ] **[Correctness] Events::Update silently ignores location_name without coordinates**
      `app/services/events/update.rb:155-158` — Location is only set when both `latitude` and
      `longitude` are non-nil. A client sending `location_name` without coordinates gets no
      error; the name is silently dropped.
      **Fix:** Allow name-only locations, or return a validation error.

- [ ] **[Correctness] ChoreRosters::DeleteChore does not verify chore belongs to roster**
      `app/services/chore_rosters/delete_chore.rb:18-20` — Only finds chore by ID, never
      validates `chore.chore_roster_id == roster_id`. Same issue in `UpdateAssignment` and
      `DeleteAssignment` (assignment not verified against roster in URL).
      **Fix:** Add ownership validation in each service.

- [ ] **[Correctness] Expense date validation compares strings, not Date objects**
      `app/services/expenses/create.rb:76`, `expenses/update.rb:107` — `start_date > end_date`
      compares raw strings before parsing. Works for ISO-8601 but fragile.
      **Fix:** Parse dates first, then compare Date objects.

- [ ] **[Correctness] Users route: empty lat/lng becomes 0.0 instead of nil**
      `app/routes/users.rb:43-44` — `"".to_f` returns `0.0`, setting coordinates to the Gulf of
      Guinea. The events route handles this correctly with an empty-string guard.
      **Fix:** Apply the same `lat && lat != "" ? lat.to_f : nil` pattern.

### Reliability

- [ ] **[Reliability] No database connection or statement timeouts**
      `config/database.rb:14` — No `pool_timeout`, `connect_timeout`, or `statement_timeout`.
      Slow queries or deadlocks hang indefinitely, eventually exhausting the connection pool.
      **Fix:** Add `pool_timeout: 5`, `connect_timeout: 5`, and `SET statement_timeout = '30s'`.

- [ ] **[Reliability] Dead WebSocket connections not cleaned up on broadcast failure**
      `app/websocket/connection_manager.rb:89-94` — When `connection.websocket.write` raises,
      the connection is logged but not unregistered. Dead connections accumulate and cause
      repeated failed writes.
      **Fix:** Call `unregister(connection_id)` in the rescue block.

- [ ] **[Reliability] Idempotency check-then-insert has TOCTOU race**
      `app/services/events/create.rb:128-135`, `votes/upsert.rb:37-42`, `expenses/create.rb:140-147` —
      Two concurrent requests with the same client ID both pass the find check, then one hits
      `UniqueConstraintViolation`.
      **Fix:** Rescue `UniqueConstraintViolation` and re-fetch, or use `INSERT ... ON CONFLICT`.

### Observability

- [ ] **[Observability] No service-layer logging for any mutation**
      All services in `app/services/` — No log when objects are created, updated, or deleted.
      Cannot determine from logs who did what. Security-sensitive operations (login, role changes,
      user creation) are completely silent.
      **Fix:** Add INFO-level logging for security-sensitive ops, DEBUG for routine CRUD.
      Include acting user ID and target resource ID.

- [ ] **[Observability] No logging for authentication or authorization failures**
      `app/app.rb:62-74`, `app/services/auth/verify_token.rb:39-41` — Failed auth attempts
      produce no log entry. Impossible to detect brute-force or credential stuffing from logs.
      **Fix:** Log failures at WARN level with failure reason and request IP.

- [ ] **[Observability] No request-level exception logging**
      `lib/request_logger.rb` — Only logs successful responses. Unhandled exceptions produce
      a `500` status line with no exception class, message, or backtrace.
      **Fix:** Add `rescue StandardError => e` that logs the exception before re-raising.

- [ ] **[Observability] Silent email delivery failures**
      `app/mailers/base.rb:37-38` — `deliver` rescues and swallows exceptions. The caller
      returns success ("login link sent") even when no email was delivered.
      **Fix:** Re-raise in synchronous `deliver` so callers can handle failure. Add error
      tracking for `deliver_later`.

- [ ] **[Observability] Sensitive tokens logged at DEBUG level**
      `app/services/auth/create_login_link.rb:46`, `invites/create.rb:107`, `invites/accept.rb:138`,
      `invites/remind.rb:95`, `users/request_email_change.rb:106` — Full login links and invite
      URLs logged only in development mode via `APP_ENV == "development"` check.

### Performance

- [ ] **[Performance] Missing indexes on 5 foreign key columns**
      `task_items.task_list_id`, `task_lists.workspace_id`, `expenses.event_id`,
      `settlements.event_id`, `settlement_transfers.settlement_id` — All used in queries
      but have no index (PostgreSQL does not auto-create indexes for FKs).
      **Fix:** Add a single migration with all 5 indexes.

- [ ] **[Performance] N+1 queries in PoolSerializer**
      `app/serializers/pool_serializer.rb:27` — `add_member_from_membership` calls `User.find`
      per member. `add_chore_roster` cascades to per-chore `ChoreAssignment` queries. Also,
      `ids_for_X` + `for_X` pattern issues duplicate queries to the same table.
      **Fix:** Batch-load users in WorkspaceSync. Load all assignments per roster in one query.
      Derive IDs from loaded objects instead of separate queries.

- [ ] **[Performance] Broadcast storm in ChoreRosters::Autofill**
      `app/services/chore_rosters/autofill.rb:67-69,142-161` — Each deleted and created
      assignment fires a separate `pg_notify`. A 7-day event with 5 chores can produce 90+
      notifications. Row-by-row INSERTs compound the issue.
      **Fix:** Use `multi_insert` for batch writes. Consolidate into a single "roster changed"
      broadcast.

### Operability

- [ ] **[Operability] Migrations run while old code serves traffic**
      `lib/capistrano/tasks/database.rake:16` — Migrations execute during `deploy:updated`,
      before the app restarts. Destructive migrations (column drops, NOT NULL) would break the
      running code. Historical migration 002 already set this precedent.
      **Fix:** Document that all migrations must be additive. Consider splitting destructive
      changes across two deploys.

- [ ] **[Operability] Rakefile db:rollback bug destroys all tables**
      `backend/Rakefile:65` — `target: Sequel::Migrator.run(DB, "db/migrations", target: 0) - 1`
      evaluates the inner call first, which undoes ALL migrations before the outer call runs.
      **Fix:** Read current schema version and subtract 1 instead.

- [ ] **[Operability] WebSocket listener has no graceful shutdown hook**
      `config.ru:13`, `app/websocket/listener.rb:26-31` — No `at_exit` or signal handler calls
      `Listener.stop`. SIGTERM kills the listener thread mid-operation, orphaning the PG
      connection.
      **Fix:** Add `at_exit { Websocket::Listener.stop }` in config.ru.

### Testability

- [ ] **[Testability] 9 of 13 route files have no integration tests**
      Missing route specs for: `events.rb`, `expenses.rb`, `settlements.rb`, `chore_rosters.rb`,
      `invites.rb`, `members.rb`, `workspaces.rb`, `ws.rb`, `test.rb`. Route tests cover auth
      guards, parameter coercion, and HTTP status codes that service tests miss.
      **Fix:** Prioritize events (largest), settlements (complex routing), and invites
      (mixed auth).

- [ ] **[Testability] Shallow Expenses::Create spec (3 cases for 7+ failure paths)**
      `spec/services/expenses/create_spec.rb` — Only tests RSVP validation and happy path.
      Missing: empty description, length limits, amount bounds, date validation, idempotency.
      **Fix:** Add test for each validation branch.

---

## Minor

### Correctness

- [ ] **[Correctness] ChoreRosters::UpdateAssignment cannot clear a note**
      `app/services/chore_rosters/update_assignment.rb:38` — `updates[:note] = note if note`
      ignores empty string and nil. User cannot remove an existing note.
      **Fix:** Change to `updates[:note] = note unless note.nil?`.

- [ ] **[Correctness] Events::Update allows clearing dates on event with active poll**
      `app/services/events/update.rb:141-148` — Dates can be manually cleared even when a
      resolved poll set them, bypassing poll lifecycle.
      **Fix:** Validate that dates cannot be cleared if a date poll exists.

- [ ] **[Correctness] auth/me could crash if user deleted between session check and fetch**
      `app/routes/auth.rb:86-98` — `User.find(session.user_id)` returns nil if user was deleted.
      No nil guard before accessing user fields.
      **Fix:** Add `return request.halt [404, ...] unless user`.

- [ ] **[Correctness] PoolSerializer#add_all silently ignores unknown types**
      `app/serializers/pool_serializer.rb:173-178` — Unknown type strings are skipped without
      warning. Could hide bugs from misspelled type names.
      **Fix:** Log a warning for unknown types.

- [ ] **[Correctness] Votes::Upsert / Rsvps::Upsert race condition**
      `app/services/votes/upsert.rb:37-42,121-155` — Idempotency check runs outside transaction.
      Concurrent request could cause `UniqueConstraintViolation`.
      **Fix:** Use `INSERT ... ON CONFLICT` or wrap in transaction with rescue.

### Reliability

- [ ] **[Reliability] Listener error logging omits backtrace**
      `app/websocket/listener.rb:132`, `broadcaster.rb:49`, `connection_manager.rb:93` — Error
      logging uses only `e.message`. No `e.class` or backtrace. Same pattern in all WebSocket
      layer error handling.
      **Fix:** Log `e.class` and `e.backtrace&.first(5)`.

- [ ] **[Reliability] Listener @running flag is not thread-safe**
      `app/websocket/listener.rb:26-49` — Read/written from multiple threads without
      synchronization. Safe on MRI due to GIL but technically a data race.
      **Fix:** Use `Mutex`-protected accessor or `Concurrent::AtomicBoolean`.

- [ ] **[Reliability] Autofill can produce very large transactions**
      `app/services/chore_rosters/autofill.rb:104-163` — 30-day event with many chores generates
      hundreds of INSERTs + broadcasts in a single transaction.
      **Fix:** Batch inserts with `multi_insert`. Consolidate broadcasts.

### Security

- [ ] **[Security] WebSocket error message uses string interpolation instead of JSON serialization**
      `app/routes/ws.rb:18` — `"{\"error\":\"#{error_msg}\"}"` — Manual JSON construction.
      Could produce invalid JSON if message contains quotes.
      **Fix:** Use `{ error: error_msg }.to_json`.

- [ ] **[Security] Login links logged at INFO could leak in misconfigured production**
      See observability finding above. Defense in depth concern.

- [ ] **[Security] Test reset endpoint accessible if RACK_ENV defaults to development**
      `app/routes/test.rb:8` — `POST /api/test/reset` truncates all tables. If production
      deployment fails to set `RACK_ENV=production`, this endpoint is exposed.
      **Fix:** Invert the check to explicitly block production, or add a startup assertion.

### Observability

- [ ] **[Observability] Email addresses logged at INFO level (PII)**
      `app/mailers/base.rb:34-38` — Every email send logs the full recipient address.
      **Fix:** Log truncated email or just the domain.

- [ ] **[Observability] WebSocket connection lifecycle not logged**
      `app/websocket/connection_manager.rb:27-54` — No logging for connect, disconnect, or
      workspace switch. Cannot determine concurrent connection count from logs.
      **Fix:** Add INFO-level register/unregister logging.

- [ ] **[Observability] Rate limiting events not logged**
      `lib/rate_limiter.rb:77-79` — Throttled requests produce a 429 in request logs but no
      detail about which throttle rule triggered.
      **Fix:** Add `Rack::Attack.throttled_callback` with WARN-level logging.

### Performance

- [ ] **[Performance] Missing index on chores.chore_roster_id**
      `db/migrations/018_add_chore_rosters.rb:14-22` — FK column used in queries without index.
      **Fix:** Add to the index migration.

- [ ] **[Performance] Missing index on deleted_items.(object_type, object_id)**
      Multiple models call `DB[:deleted_items].where(object_type: X, object_id: id).first` in
      `find_result`. Only indexed on `(workspace_id, deleted_at)`.
      **Fix:** Add index `[:object_type, :object_id]`.

- [ ] **[Performance] deleted_items table grows unbounded**
      `db/migrations/004_add_partial_sync.rb` — No cleanup mechanism. Every delete appends a row.
      **Fix:** Add periodic cleanup for rows older than the 7-day retention period.

- [ ] **[Performance] Settlements::Create loads event expenses twice**
      `app/services/settlements/create.rb:123,132` — Two separate `Expense.for_event` calls.
      **Fix:** Load once and reuse.

- [ ] **[Performance] Row-by-row deleted_items INSERTs**
      `autofill.rb:68`, `clear_unpinned.rb:41`, `reopen.rb:71`, `clear_completed.rb:29` —
      Each deleted item inserted individually.
      **Fix:** Use `multi_insert`.

### Operability

- [ ] **[Operability] In-memory rate limiter state lost on restart**
      `lib/rate_limiter.rb:9-45` — Memory-backed store resets on every deploy, allowing bursts.
      Acceptable for single-server but fragile.

- [ ] **[Operability] Hardcoded Ruby version paths in systemd unit**
      `config/deploy/tayaway-falcon.service:14-16` — `GEM_HOME` and `GEM_PATH` reference
      `ruby/4.0.0` while PATH references `ruby/4.0.1`. Inconsistent and requires manual update
      on Ruby upgrades.
      **Fix:** Generate the systemd unit from a template during deploy.

- [ ] **[Operability] SMTP credentials required at boot even if unused**
      `app/mailers/base.rb:59-62` — Missing SMTP env vars crash the entire app at startup.
      **Fix:** Defer the requirement to first email send.

### Testability

- [ ] **[Testability] Invites::Remind rate-limiting logic is untested**
      `app/services/invites/remind.rb:61-69` — Time-sensitive comparison with 24h cooldown.
      Regressions would go undetected.
      **Fix:** Add spec with time manipulation.

- [ ] **[Testability] WebSocket infrastructure is entirely untested**
      `app/routes/ws.rb`, `app/websocket/` — Connection manager, message handler, listener,
      and broadcaster have no tests.
      **Fix:** At minimum, unit test `Broadcaster` payload format.

### Maintainability

- [ ] **[Maintainability] WorkspaceMembership.to_api_hash returns wrong objectType**
      `app/models/workspace_membership.rb:19` — Returns `"workspaceMembership"` but the registry
      and serializer both use `"member"`. Method is never called but creates confusion.
      **Fix:** Remove `to_api_hash` or change objectType to `"member"`.

- [ ] **[Maintainability] Duplicated coordinate parsing in User and Event models**
      `app/models/user.rb:76-80`, `app/models/event.rb:106-110` — Identical POINT parsing logic.
      **Fix:** Extract into a shared `PointParser` utility.

- [ ] **[Maintainability] Duplicated validation logic across service pairs**
      `events/create.rb` + `events/update.rb` (text lengths, dates),
      `expenses/update.rb` + `expenses/delete.rb` (check_not_settled, check_owner),
      `task_lists/update_item.rb` + `task_lists/delete_item.rb` (validate_belongs_to_list).
      **Fix:** Extract shared validators into modules.

- [ ] **[Maintainability] Duplicated find_result pattern across 8+ models**
      `Event`, `TaskList`, `TaskItem`, `Expense`, `Settlement`, `SettlementTransfer`, `Chore`,
      `ChoreRoster`, `ChoreAssignment` — Nearly identical find-or-check-deleted logic.
      **Fix:** Extract into a `Findable` concern.

- [ ] **[Maintainability] Dead code: 5 unused methods**
      `Event.for_user` (event.rb:49), `User.find_by_email_exact` (user.rb:51),
      `TaskItem.ids_for_task_list` (task_item.rb:47), `require_admin_or_owner!` (app.rb:82),
      `all_ordered` on User/Event/Workspace.
      **Fix:** Remove unused methods.

- [ ] **[Maintainability] Duplicated UUID_REGEX in Votes::Upsert and Rsvps::Upsert**
      `votes/upsert.rb:18`, `rsvps/upsert.rb:16` — Same regex defined as private constant.
      **Fix:** Use shared `UUID::REGEX` instead.

- [ ] **[Maintainability] Magic numbers repeated without named constants**
      Session expiry (`EXPIRY_DAYS * 24 * 60 * 60` in 3 places), settlement epsilon (`0.005`
      used 4 times), validation limits (255, 5000, 1_000_000 across multiple services).
      **Fix:** Define named constants.

---

## Suggestions

- [ ] **[Observability] Switch to structured (JSON) logging in production**
      `config/environment.rb:25-29` — Plain-text logs are hard to filter/aggregate. Timestamps
      are discarded in the formatter.

- [ ] **[Operability] Health check should verify database connectivity**
      `app/routes/health.rb` — Returns healthy unconditionally. Add `DB.test_connection`.

- [ ] **[Operability] Make DB pool size configurable via env var**
      `config/database.rb:14` — Hardcoded `max_connections: 16`. Should match Falcon concurrency.

- [ ] **[Performance] No pagination on list endpoints**
      All list endpoints return every row without limits. Consider adding defaults with cursor
      or offset pagination.

- [ ] **[Performance] WorkspaceSync issues 16+ queries on every workspace switch**
      `app/services/sync/workspace_sync.rb:38-44` — One `changed_since` query per object type.
      Consider optimizing full-sync path.

- [ ] **[Security] Consider `__Host-` cookie prefix in production**
      `app/app.rb:33` — Would enforce Secure, exact host, and Path=/ for additional protection.

- [ ] **[Maintainability] Route files use `# typed: false` — document exception in CLAUDE.md**
      All route files deviate from the `# typed: true` convention due to Roda DSL limitations.

- [ ] **[Maintainability] Extract shared login link creation logic**
      `invites/accept.rb:112-138` and `auth/create_login_link.rb:33-73` share nearly identical
      token creation, JWT building, and email sending logic.

- [ ] **[Correctness] Concurrent settlement creation could double-settle expenses**
      `app/services/settlements/create.rb:48-51,93-126` — Two concurrent settlements could each
      claim a subset of unsettled expenses. Consider `SELECT ... FOR UPDATE` or a uniqueness
      constraint.
