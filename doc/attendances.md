# Attendances

> **Status: target architecture.** The code currently implements the `rsvps`
> model this document replaces. Nothing here is built yet; we migrate toward it
> incrementally (see "Migration staging" at the end). When the migration is
> done, the "Current model" section and the staging plan can be deleted.

Attendance answers "who is at this event, on which days". RSVP is the *action*
of answering that question — it creates and updates attendance rows; it is not
itself a stored thing.

## Current model, and why it's being replaced

Today there is exactly one `rsvps` row per `(event_id, user_id)` (DB unique
constraint). Plus-ones are anonymous per-day integer counts embedded in the
row's `attendance` jsonb, with a dual wire shape per entry: a bare ISO string
for a guest-free day, or `{ date, plusOnes }` when guests come along.

Consequences:

- **Guests have no identity.** They are steppers counting to N — no names, no
  history across events, re-entered every trip.
- **Settlement treats guests as head-weights.** Each day is worth
  `1 + plusOnes` heads, silently absorbed into the host's share
  (`Settlements::BalanceMath`). Guests can never be shown, itemized, or split
  differently.
- **Chores can't involve guests.** Autofill availability is keyed purely on
  `user_id`; guests are dropped on the floor (`Rsvp#effective_dates`).
- **The dual wire shape is parsed everywhere.** `Rsvp.wire_attendance_day`,
  `parse_attendance_entry`, the max-plusOnes dedupe in `Rsvps::Upsert`, and
  mirrored logic in `frontend/src/utils/event.ts`, `days.ts`, and
  `settlement.ts` all exist only to carry counts inside day entries.

## Target model

Two tables. One row in `attendances` per person per event; `guests` gives
non-member people a persistent, workspace-level identity.

```
guests            -- workspace-scoped identity for non-members
  id uuid PK
  workspace_id    → workspaces, cascade
  name            text
  placeholder     boolean NOT NULL default false -- backfill-synthesized; see below
  created_by_user_id              -- no on_delete (NO ACTION), per 039 precedent
  created_at / updated_at

attendances       -- one row per person per event
  id uuid PK      -- client-generated
  event_id        → events, cascade
  user_id         → users,  nullable ┐  CHECK: exactly one set
  guest_id        → guests, nullable ┘  NO ACTION — app-level delete guard
  host_user_id    → users; required for guest rows, NULL for member rows (NO ACTION)
  status          text: pending | going | declined
  days            jsonb, nullable -- flat ["2026-07-01", ...]; NULL = whole event
  created_by_user_id              -- actor who filed it (may differ from subject)
  created_at / updated_at
  UNIQUE (event_id, user_id)  WHERE user_id  IS NOT NULL
  UNIQUE (event_id, guest_id) WHERE guest_id IS NOT NULL
```

Notes:

- `days` is a flat array of ISO date strings again — with guests as rows, the
  per-entry `plusOnes` object shape disappears entirely. `NULL` means "the
  whole event", same as today. If per-day metadata is ever needed (meals,
  overnight stays), `days` can become a child table then; nothing forecloses
  it.
- There are no legacy `start_date`/`end_date` hull columns. The new table
  starts clean.
- `host_user_id` is per-event on purpose: the same guest can be brought (and
  paid for) by different members on different trips.
- Guest identity is workspace-scoped because plus-ones are overwhelmingly
  recurring partners and kids. Adding a guest to an event offers recent
  guests before creating a new one. `placeholder` guests (synthesized by the
  backfill from anonymous plus-one counts) are excluded from that picker;
  renaming one clears the flag.
- `days` carries meaning only when `status = going`. Presence math (display,
  settlement, chore availability) counts `going` rows only; on `pending` and
  `declined` rows `days` is noise, kept `NULL`. This keeps `NULL` from being
  overloaded — it always reads "whole event", it just isn't read at all
  outside `going`.
- The status enum is uniform across members and guests. What's guest-specific
  is *who* transitions it: a guest never files anything — members create them
  as `going`, a date reset parks them at `pending` until their host
  re-confirms, and removal flips them to `declined` (see Lifecycle).
- `attendances.guest_id` is `NO ACTION` deliberately, not `RESTRICT`:
  NO ACTION checks at statement end, so a workspace delete — which cascades
  workspace→guests and workspace→events→attendances in the same statement —
  succeeds, while a direct `DELETE FROM guests` with live references still
  fails. Deleting a guest is guarded app-side: allowed only when no
  attendances reference them (`:has_attendances`); otherwise rename is the
  remedy. No archive mechanism until the picker proves to need one.

## The attendee union — containment contract

An **attendee** is "the person behind an attendance row": a member (via
`user_id`) or a guest (via `guest_id`). The union is *not* eliminated by this
design — it is given a single home and a primary key.

The rules:

1. **The `user_id XOR guest_id` pair exists only in `attendances`.** Any table
   that needs to point at an attendee references `attendance_id` — a single
   FK — never its own user/guest pair.
2. **Exactly two places may look inside the union:**
   - Backend: the `Attendance` model exposes an `attendee` value object
     (`display_name`, `user_id?`, `guest?`, `billing_user_id`). Services,
     serializers, and settlement consume that.
   - Frontend: one hydration composable joins each attendance with its user
     or guest from the pool and hands components a uniform hydrated attendee.
3. Everything else — display, counting, availability, proportional shares —
   consumes resolved attendees and never branches on `guestId`. This is
   grep-enforceable.

The containment has a floor: guests genuinely lack capabilities (no login, no
push notifications, no IBAN), so a notification site or payment site resolves
to the host or skips — in any design. The contract covers *routine* consumers.

Deliberately **not** chosen: a unified `people` table where members and guests
are the same entity. Auth, sessions, votes, notifications, and payment are
irreducibly user-keyed, so a person indirection would force user↔person
translation at every boundary forever and give every human two IDs on the
client. Guests are a different kind of thing; the XOR is honest about that.
The one thing `people` would buy — promoting a guest to a member — is a rare
one-transaction row rewrite.

## Who references what

The rule for every foreign key: **presence-side concepts reference
`attendances`; money-side and identity-side concepts reference `users`.** The
attendance row is the join point that resolves presence into a billable user.

| Table | End state | Why |
|---|---|---|
| `chore_assignments` | → `attendance_id` (done; `user_id` mirror drops later) | Doing a chore is presence; unlocks guests doing chores |
| `expense_participants` | → `attendance_id` (later phase) | Participation is consumption, i.e. presence; enables guest participants |
| `expenses` (payer) | stays `user_id` | Paying is money; guests have no account or IBAN |
| `settlement_transfers` | stays `user_id` | Money movement between account holders |
| `votes` | stays `user_id` | Member decision; happens before attendances exist |
| `task_items` (claimed-by) | stays `user_id` for now | Presence-flavored; move only if guests should claim tasks |
| audit, notifications, push, `created_by_*` | stays `user_id` | Actors are authenticated users |

Settlement sits exactly on the seam and splits internally: shares accrue per
**attendance** (each attended day = 1 head; no weights), then `BalanceMath`
resolves each attendance to its billing user — `attendee.user_id` for members,
`host_user_id` for guests — and everything downstream (balances, transfers,
snapshots) is user-keyed money. The settlement snapshot stores both the
attendee identity (audit: "who was counted") and the resolved billing user
(math). `BalanceMath` keeps tolerating older snapshot shapes, as it already
does for the pre-plus-ones flat `dates` form.

Two facts that shape the migration: the stored snapshot is **audit-only** —
all live math (create, preview, drift) recomputes from current rows — so only
the snapshot writer and the model-level parser change shape; and the balance
math is **fully mirrored in `frontend/src/utils/settlement.ts`**, computing
live from pool objects, so the backend and frontend must switch input source
in the same release or previews diverge from settlements.

## Lifecycle: rows are long-lived, status transitions

Because presence-side tables FK into `attendances`, hard-deleting an
attendance row would silently rewrite chore history and expense splits. So
attendance rows, once created, transition status instead of being deleted:

- **No response yet**: no row (first RSVP creates it), or an existing row
  reverted to `pending`. Today "no response" is *derived from row absence*
  (there is no stored pending state), so every frontend site with that
  assumption must learn the second form — notably `useEventsNeedingRsvp`
  treats any row as "answered" and would silently stop reminding people
  after a date reset.
- **Decline**: member rows flip to `declined` (row kept, `days` → NULL).
  A member cannot decline while they have `going` guest rows on the event
  (`:has_going_guests`, modal: remove your guests first) — otherwise their
  guests would keep billing a host who isn't coming. Pending guests don't
  block.
- **Removing a guest**: flip their row to `declined` — same verb, uniform
  rule, no conditional delete. Re-adding the guest upserts the same row back
  to `going` via `UNIQUE (event_id, guest_id)`.
- **Event date change / poll reopen**: keep the people, clear the answers.
  All rows — members and guests alike — revert to `pending` with
  `days = NULL`; the roster survives, hosts re-confirm their guests when
  they re-pick their own days. This deliberately replaces today's behavior
  of bulk-deleting all RSVPs (a client-side best-effort loop in
  `EventPage.vue` for date edits; server-side in `DatePolls::Reopen`). Both
  flows move server-side into the owning service, transactional, broadcast
  per row. Ordering detail: `Events::OnDetailsChanged` computes its
  notification recipients from *going* rows — resolve recipients before the
  revert (notify the people who had answered), then reset, in one
  transaction. The `EventPage.vue` confirm modal copy changes accordingly:
  the roster is kept, only day picks are cleared.
- **Hard delete** happens only via the event's own cascade (everything dies
  together) or workspace/user deletion cascades.
- Removing a person with expense participation gets a guard, mirroring
  today's "cannot decline while you have expenses on this event".

The chore-assignment FK move (later phase) needs one deliberate call on
cascade-vs-keep-history for the residual hard-delete paths; clear-not-delete
makes it mostly moot, but decide it explicitly when that phase lands.

## Sync, pool, and naming

- New object types `attendance` and `guest`, registered in `ObjectRegistry`
  with camelCase `client_type` (tombstones and broadcasts must use it — see
  the sync-audit lesson from PR #555).
- The day-set field on the wire is `days`, not `attendance` — avoiding a
  collision with the legacy `rsvp.attendance` field while both object types
  coexist during migration.
- `EventSerializer` gains `attendanceIds`; `rsvpIds` remains until old
  clients drain.
- Every bulk mutation (date reset, poll reopen) broadcasts per row —
  `object_changed` for status reverts, `object_deleted` + `deleted_items`
  tombstones for true deletes. The pool never prunes children on parent
  updates.
- The pool's `CASCADE_RULES` gain `event → attendance` and
  `workspace → guest`, or removing a parent leaks orphaned children (unknown
  child types are silently dropped — the PR #555 failure mode).
- Mutations flow through the offline command queue as today. The
  new-guest-plus-attendance flow is **one command**: `attendances.upsert`
  accepts an inline `guest: { id, name }` payload and creates the guest in
  the same transaction when it doesn't exist yet (keyed by the
  client-generated guest id, so replays are idempotent). This sidesteps a
  cross-resource ordering hazard rather than fixing it in the queue: the
  queue is FIFO only in its offline drain loop — when online, commands
  execute directly and order only per resource key, so a separately queued
  guest-create could be overtaken by its attendance-upsert the moment
  connectivity returns (FK violation, command dropped, rollback).
  Standalone guest commands (rename, delete) stay separate; they never race
  a create because the client only offers existing guests for those.
- Upserts are idempotent on the partial unique indexes, keyed by
  client-generated `id`. On conflict the server keeps the existing row's id
  (as `Rsvps::Upsert` does); the attendance store drops the differently-id'd
  optimistic temp when the response arrives, same as `rsvps.ts` does today.
  (A queued create that loses such a race can still leave a phantom temp —
  a rare wart rsvps already have; not worth queue-level machinery.)

## Authorization

Maximally open, matching today's RSVP policy: any workspace member may create,
edit, or delete any attendance and any guest. `Subjects.validate` semantics
carry over — the subject must be a workspace member (or a workspace guest);
`created_by_user_id` records the actor and is never overwritten on conflict,
so the original filer sticks. A trivial `AttendancePolicy`/`GuestPolicy` per
`doc/authorization.md` conventions, plus temporary-state blockers where the
lifecycle guards need them: `:has_expenses` (decline, as today),
`:has_going_guests` (member decline), `:has_attendances` (guest delete). All
three are invariants with a path forward → MODAL in `usePermission.ts`.

## What this unlocks

- Guests with names and history: "Emma (guest of Sanne)" instead of a counter,
  and the same Emma next trip.
- Settlement can itemize guests per host, and later support per-guest factors
  (kids count half) via the existing `expense_participants.factor` mechanism.
- Chores for guests: include guest attendances in autofill availability, with
  a per-attendance "does chores" opt-out (kids). Reminders for guest
  assignments notify the host. Stale-assignment detection gets simpler: an
  assignment is stale iff its attendance's `days` no longer cover its date —
  a direct join instead of re-deriving availability per user.
- The dual wire shape and all of its parsing (backend and the three frontend
  utils) is deleted.

## Migration staging

All schema changes additive; destructive steps use the two-deploy pattern
(`doc/database-migrations.md`). Each phase is independently shippable.

The ordering principle: **rsvps stay the settlement source of truth until
phase 5.** Guest data on the attendance side is read by nothing
money-critical before then, so the write path never synthesizes guests —
synthesis lives only in the (idempotent) backfill converter, run at phase 2
and re-run once at the phase-4 cutover. Coexistence is handled by rollout
pragmatism, not machinery: attendance rarely changes day-to-day here, so
phases 4 and 5 deploy back-to-back with a short announced hold-off on
attendance edits, instead of two-way mirroring. Each divergence window is
called out below rather than engineered away.

1. **Tables + services.** Create `guests` and `attendances`;
   `Attendances::Upsert` / `Guests::Create` etc. (wrapped in
   `Auditable.around` like `Rsvps::Upsert`); serializers, registry entries,
   policies.
2. **Backfill + dual-write.** `Rsvps::Upsert` mirrors *member* rows into
   `attendances`. Backfill converts existing rows; embedded `plusOnes`
   synthesize per-event `placeholder` guests deterministically — the max
   concurrent count for an event becomes N guests ("Guest 1 (host)", …),
   guest *k* attending the days where the count ≥ k. Renameable afterwards;
   hidden from pickers until renamed. The converter is idempotent per
   `(event, host)` and touches only placeholder-flagged guests — it gets
   re-run in phase 4. plusOnes edits between now and phase 4 land only in
   rsvps; that's fine, because nothing reads attendance-side guests yet.
3. **Move member-keyed readers, one PR each:** chore autofill +
   `reassign_stale`, then `EventSerializer` (`attendanceIds`). Member rows
   are dual-written so these can't diverge. Settlement and guest-facing
   views deliberately do **not** move here.
4. **New write path + views.** RSVP UI writes attendances/guests through the
   command queue and the frontend displays attendances (named guests appear);
   `CACHE_VERSION` bump. The old rsvp endpoints stay up for stale clients
   with the phase-2 dual-write still running (rsvp → attendance, member
   fields). There is **no reverse mirroring** — new-UI edits don't reach
   rsvps. Re-run the backfill converter once at this cutover to catch the
   phase-2→4 edit gap; plusOnes arriving in old-shape writes after cutover
   are ignored on the attendance side (log a warning to spot stragglers).
5. **Settlement flip.** `BalanceMath`'s input (create, preview, drift) and
   `frontend/src/utils/settlement.ts` move from rsvps to attendances **in
   the same release** (both compute live). Deploy promptly after phase 4:
   between the two deploys, new-UI attendance edits are invisible to
   settlement, and stale-client edits are invisible to the new UI. Accepted
   deliberately — announce a short hold-off on attendance edits instead of
   building mirroring for a one-day window. Blocks phase 7.
6. **Server-side resets.** Move the date-change reset out of `EventPage.vue`
   into `Events::Update`; switch it and `DatePolls::Reopen` to
   clear-not-delete semantics (all rows → `pending`, per-row broadcasts,
   recipients resolved before the revert).
7. **Retire rsvps.** Stop dual-writing, drop `rsvp` from
   the pool and registry, remove the rsvp endpoints, model, services, and
   readers (all code-side, done once stale clients drained). The `rsvps`
   table and its rows stay frozen in place as history; dropping the table
   (which also retires the legacy `start_date`/`end_date` hull columns left
   over from the come-and-go migration, PR #527) is a separate two-deploy
   follow-up.
8. **Later, on demand:** `chore_assignments` → `attendance_id` — **done**
   (migrations 052/053: backfill by joining `(event_id, user_id)`, partial
   unique on `(chore_id, attendance_id, date)`, guest holders enabled behind
   `MIN_SUPPORTED_VERSION` 2). Remaining: the two-deploy drop of the
   `user_id` mirror column once pre-2 clients drain, and
   `expense_participants` → `attendance_id` when guest participation is
   wanted.
