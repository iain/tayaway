# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

> **Keep this file up to date.** When you add routes, models, services, database tables, or change architectural patterns, update the relevant sections of this document. Accurate documentation prevents hallucinated APIs and wrong assumptions in future sessions.

## Project Overview

Tayaway is a real-time collaborative event planning app. Users authenticate via magic link email, belong to workspaces, and create events with date polls that members vote on. The app syncs all state in real-time via WebSockets and PostgreSQL LISTEN/NOTIFY.

**Monorepo layout:** pnpm workspace with `frontend/` and `e2e/` as packages. `backend/` is a standalone Ruby app (not a pnpm package).

## Commands

All commands run through mise:

```bash
mise run dev              # Start frontend (5173) + backend (9292)
mise run ci               # All CI checks (lint, typecheck, tests, e2e) in parallel
mise run test             # All tests (frontend + backend + e2e)
mise run test_backend     # RSpec tests only
mise run test_frontend    # Vitest tests only
mise run test_e2e         # Playwright e2e tests (Playwright starts its own servers)
mise run lint             # ESLint + RuboCop
mise run typecheck        # vue-tsc + Sorbet
mise run db_migrate       # Run Sequel migrations
mise run db_reset         # Drop, create, migrate database
```

**Before committing:** Always run `mise run ci` and ensure it passes before creating a commit.

Run a single test:

```bash
cd backend && bundle exec rspec spec/path/to/spec.rb
cd frontend && pnpm exec vitest run src/path/to/file.spec.ts
```

**Three databases:** `tayaway_development`, `tayaway_test`, `tayaway_e2e`. When resetting, also reset test/e2e:

```bash
RACK_ENV=test bundle exec rake db:reset
RACK_ENV=e2e bundle exec rake db:reset
```

## Architecture

```
frontend/                   Vue 3 + TypeScript + Vite + Tailwind CSS + Pinia
  src/api/client.ts         Fetch-based HTTP client (not Axios); auto-imports pool objects from responses
  src/pages/                Page components (Home, Login, Events, Vote, Profile, Members)
  src/components/           Reusable components (events/, calendar/, votes/, form/, common/)
  src/composables/          Vue composables (useHydratedEvent, useCalendar, useMutation, useDarkMode)
  src/stores/               Pinia stores (objectPool, websocket, commandQueue, auth, workspace, events, votes, ...)
  src/types/pool.ts         Object pool type registry (ObjectTypeMap, OBJECT_TYPES)
  src/router/               Vue Router with auth guards

backend/                    Ruby 4 + Roda + Sequel + Falcon + Sorbet
  app/app.rb                Main Roda app with hash_routes plugin
  app/routes/               Route files (auth, events, members, workspaces, users, chore_rosters, ws, health)
  app/models/               Immutable T::Struct models with from_row / to_api_hash
  app/services/             Business logic using Result monad (Success/Failure with bind chains)
  app/serializers/          PoolSerializer — collects related objects for normalized API responses
  app/websocket/            Listener (pg_notify), ConnectionManager, MessageHandler
  app/object_registry.rb    Central registry mapping object types to models and serializer methods
  config/environment.rb     Zeitwerk autoloader + Sorbet setup
  config/database.rb        Sequel connection
  db/migrations/            Sequel migrations

e2e/                        Playwright tests (auth, events, voting, poll lifecycle, profile)
doc/                        Architecture docs (real-time-sync.md, workspaces.md)
```

## Key Architectural Patterns

### Object Pool & Real-Time Sync

All API responses return normalized `{ objects: [...] }` payloads. The frontend stores these in a type-keyed pool (`Map<ObjectType, Map<id, PoolObject>>`). Real-time updates flow through:

1. Service mutates DB and calls `Broadcaster.object_changed(type, id, workspace_id:)`
2. PostgreSQL `NOTIFY` triggers the background `Listener` thread
3. Listener fetches full object, serializes via `PoolSerializer`, broadcasts to workspace connections
4. Frontend `importObjects()` merges by timestamp (strictly newer wins)

See `doc/real-time-sync.md` for full details including parent timestamp touching.

### Result Monad (Backend Services)

Services return `Result[Success[T], Failure[ServiceError]]` and compose with `.bind`:

```ruby
def call
  validate_input
    .bind { find_poll }
    .bind { check_poll_open }
    .bind { create_vote }
    .fmap { |vote| serialize(vote) }
end
```

Use `T.cast` when `fmap` changes the generic type to satisfy the Sorbet type checker.

### Hydration (Frontend)

`useHydratedEvent` denormalizes pool objects into nested structures for component consumption. The pool stays normalized for sync efficiency; hydrated views are computed properties.

### Workspace Scoping

All domain data belongs to a workspace. Backend routes verify membership. The frontend switches one workspace at a time via WebSocket `switch_workspace` message. See `doc/workspaces.md`.

## Data Model

```
users              id (UUID), email (CITEXT), name, phone_number (TEXT nullable), birthday (DATE nullable), location_name (TEXT nullable), location_coordinates (POINT nullable), iban (TEXT nullable), timestamps
sessions           id, user_id, token, expires_at (30 days)
magic_link_tokens  id, user_id, token, email, expires_at (15 min), used_at
email_change_tokens id, user_id, token (hashed), email (CITEXT — current email), new_email (CITEXT), expires_at (15 min), used_at, timestamps
ws_tickets         id, user_id, ticket (JWT), used_at

workspaces              id, name, timestamps
workspace_memberships   id, workspace_id, user_id, role (owner/admin/member), unique(workspace_id, user_id)

events             id, workspace_id, user_id (nullable, set null on delete), name, description, start_date (nullable), end_date (nullable), location_name (TEXT nullable), location_coordinates (POINT nullable), timestamps
date_polls         id, event_id (unique, cascade), deadline, selected_date_range_id, closed_at, timestamps
date_ranges        id, date_poll_id, start_date, end_date, timestamps, check(start_date <= end_date)
votes              id, date_range_id, user_id, response (yes/no/preferably_not), comment, unique(date_range_id, user_id)
rsvps              id, event_id, user_id, attending (boolean), start_date (nullable), end_date (nullable), timestamps, unique(event_id, user_id), check(start_date <= end_date)
task_lists         id, workspace_id (FK cascade), user_id (FK set_null, nullable), name TEXT, position FLOAT (ordered within workspace), timestamps
task_items         id, task_list_id (FK cascade), user_id (FK set_null, nullable), content TEXT, completed_at (TIMESTAMPTZ nullable), position FLOAT (ordered within list), timestamps
expenses           id (UUID), event_id (FK cascade), user_id (FK set_null, nullable), settlement_id (FK settlements set_null, nullable), amount NUMERIC NOT NULL (euros), description TEXT NOT NULL, start_date DATE NOT NULL, end_date DATE NOT NULL, timestamps, check(start_date <= end_date)
settlements        id (UUID), event_id (FK cascade), user_id (FK set_null, nullable), timestamps
settlement_transfers  id (UUID), settlement_id (FK settlements cascade), from_user_id (FK set_null, nullable), to_user_id (FK set_null, nullable), amount NUMERIC NOT NULL, paid_at (TIMESTAMPTZ nullable), timestamps
chore_rosters     id (UUID PK), event_id (FK events unique cascade), user_id (FK users set_null nullable), timestamps
chores            id (UUID PK), chore_roster_id (FK cascade), name (VARCHAR 255), people_per_day (INT default 1), position (FLOAT), timestamps
chore_assignments id (UUID PK), chore_id (FK cascade), user_id (FK users cascade), date (DATE), pinned (BOOL default false), note (TEXT nullable), timestamps, unique(chore_id, user_id, date)
workspace_invites  id (UUID), workspace_id (FK cascade), invited_by (FK set_null, nullable), email (CITEXT), token (hashed), expires_at (24h), accepted_at (nullable), timestamps; partial unique(workspace_id, email) WHERE accepted_at IS NULL
```

**Hierarchy:** Workspace -> Event -> DatePoll -> DateRange -> Vote
**RSVP:** Event -> Rsvp (once event has dates set)
**Settlement:** Event -> Settlement -> SettlementTransfer; Settlement -> Expenses (via settlement_id)
**Chore Roster:** Event -> ChoreRoster -> Chore -> ChoreAssignment

**Poll lifecycle:** open -> expired (past deadline) -> resolved (closed with winner) -> can reopen
**RSVP lifecycle:** Closing a poll auto-RSVPs "yes" voters as attending. Reopening a poll deletes all RSVPs.

## API Endpoints

**Authentication (`/api/auth`)**

- `POST /magic-link` — Request magic link email
- `POST /verify` — Verify token and create session
- `GET /me` — Get current user (requires auth)
- `POST /logout` — End session (requires auth)
- `POST /ws-ticket` — Get single-use WebSocket JWT (requires auth)
- `GET /sessions` — List user's sessions (requires auth)
- `DELETE /sessions/:id` — Delete a session (requires auth)

**Events (`/api/events`)** — All require authentication + workspace membership

- `GET /` — List events in current workspace
- `POST /` — Create event
- `GET /:id` — Get event details
- `PUT /:id` — Update event (owner only)
- `DELETE /:id` — Delete event (owner only)
- `POST /:id/poll` — Create date poll
- `POST /:id/poll/close` — Close poll with selected winner
- `POST /:id/poll/reopen` — Reopen a resolved poll
- `POST /:id/poll/date-ranges` — Add date range to poll
- `DELETE /:id/poll/date-ranges/:dr_id` — Remove date range
- `GET /:id/rsvps` — Get RSVPs for event
- `POST /:id/rsvps` — Create or update RSVP
- `DELETE /:id/rsvps/:rsvp_id` — Delete RSVP
- `GET /:id/votes` — Get votes for event
- `POST /:id/votes` — Create or update vote
- `DELETE /:id/votes/:vote_id` — Delete vote

**Task Lists (`/api/task-lists`)** — All require authentication + workspace membership

- `GET /` — List task lists for workspace (workspace_id query param)
- `POST /` — Create task list
- `PUT /:id` — Update task list (name and/or position; at least one required)
- `DELETE /:id` — Delete task list
- `POST /:id/items` — Add item to list
- `PUT /:id/items/:item_id` — Update item (content, completed boolean, position, and/or task_list_id for cross-list move)
- `DELETE /:id/items/:item_id` — Delete item
- `POST /:id/clear-completed` — Delete all completed items

**Expenses (`/api/expenses`)** — All require authentication + workspace membership (via event)

- `GET /?event_id=xxx` — List expenses for event
- `POST /` — Create expense (body: event_id, description, amount, id?)
- `PUT /:id` — Update expense (creator-only; description and/or amount)
- `DELETE /:id` — Delete expense (creator-only)

**Settlements (`/api/settlements`)** — All require authentication + workspace membership (via event)

- `GET /?event_id=X` — List settlements + transfers for event
- `POST /` — Create settlement (computes balances and minimizes transfers)
- `DELETE /:id` — Delete settlement (creator or event owner)
- `PUT /transfers/:id` — Toggle paid status on a transfer
- `GET /transfers/:id/qr` — Generate EPC QR code PNG (sender-only; returns image/png)

**Chore Rosters (`/api/chore-rosters`)** — All require authentication + workspace membership (via event)

- `POST /` — Create roster (body: event_id)
- `GET /:id` — Get roster with all chores and assignments
- `DELETE /:id` — Delete roster (creator-only; cascades chores and assignments)
- `POST /:id/chores` — Add chore (name, people_per_day)
- `PUT /:id/chores/:cid` — Update chore (name, people_per_day, position)
- `DELETE /:id/chores/:cid` — Delete chore (cascades assignments)
- `POST /:id/assignments` — Pin assignment (chore_id, user_id, date, note?)
- `PUT /:id/assignments/:aid` — Update assignment (note, user_id)
- `DELETE /:id/assignments/:aid` — Remove assignment
- `POST /:id/autofill` — Delete non-pinned, re-distribute fairly
- `POST /:id/clear-unpinned` — Delete all non-pinned assignments

**Invites (`/api/invites`)** — Mixed authentication

Unauthenticated:

- `GET /info?token=JWT` — Get invite info (workspace name, email)
- `POST /accept` — Accept an invitation (creates user + membership, sends magic link)

Authenticated (admin/owner only):

- `GET /?workspace_id=X` — List pending invites
- `POST /` — Create an invitation (sends invite email)
- `DELETE /:id?workspace_id=X` — Cancel a pending invitation

**Members (`/api/members`)** — Requires authentication

- `PUT /:id` — Update member role (owner can change any; admin can change admin/member but not owner)

**Workspaces (`/api/workspaces`)** — Requires authentication

- `GET /` — List user's workspaces

**Users (`/api/users`)** — Mixed authentication

- `PUT /:id` — Update profile (name, phone, birthday, location; requires auth, owner-only)
- `POST /email-change/request` — Request email change verification link (requires auth)
- `POST /email-change/verify` — Verify email change token and update email (unauthenticated — token is proof)

**WebSocket (`/ws?ticket=<jwt>`)** — Authenticated via single-use JWT ticket

- Server sends: `authenticated`, `sync`, `broadcast`, `pong`, `error`
- Client sends: `ping`, `switch_workspace`

**Health**

- `GET /health` — Health check
- `GET /api/health` — API health check

## Object Types

These types must stay in sync between frontend and backend:

| Type                | Backend model         | Frontend pool key    | Serializer method         |
| ------------------- | --------------------- | -------------------- | ------------------------- |
| event               | `Event`               | `event`              | `add_event`               |
| datePoll            | `DatePoll`            | `datePoll`           | `add_date_poll`           |
| dateRange           | `DateRange`           | `dateRange`          | `add_date_range`          |
| vote                | `Vote`                | `vote`               | `add_vote`                |
| rsvp                | `Rsvp`                | `rsvp`               | `add_rsvp`                |
| workspace           | `Workspace`           | `workspace`          | `add_workspace`           |
| member              | `WorkspaceMembership` | `member`             | `add_member`              |
| task_list           | `TaskList`            | `taskList`           | `add_task_list`           |
| task_item           | `TaskItem`            | `taskItem`           | `add_task_item`           |
| expense             | `Expense`             | `expense`            | `add_expense`             |
| settlement          | `Settlement`          | `settlement`         | `add_settlement`          |
| settlement_transfer | `SettlementTransfer`  | `settlementTransfer` | `add_settlement_transfer` |
| chore_roster        | `ChoreRoster`         | `choreRoster`        | `add_chore_roster`        |
| chore               | `Chore`               | `chore`              | `add_chore`               |
| chore_assignment    | `ChoreAssignment`     | `choreAssignment`    | `add_chore_assignment`    |
| workspace_invite    | `WorkspaceInvite`     | `workspaceInvite`    | `add_workspace_invite`    |

Defined in: `backend/app/object_registry.rb` and `frontend/src/types/pool.ts`

**Note:** The `member` pool object includes a `userId` field that maps to the underlying user, plus contact fields from the user: `phoneNumber`, `birthday`, `locationName`, `latitude`, `longitude`, `hasIban` (boolean). The actual IBAN value is only available to the owner via `/api/auth/me` — it is never broadcast to other members. EPC QR codes are generated server-side at `GET /api/settlements/transfers/:id/qr`. Domain objects (event, vote, rsvp, taskList, taskItem, expense) carry `userId` directly — the frontend uses `pool.findBy('member', 'userId', obj.userId)` to resolve the member.

## Adding a New Object Type

1. **Backend model:** Create `T::Struct` in `app/models/` with `from_row` and `to_api_hash`
2. **Serializer:** Add `add_<type>` method to `PoolSerializer`
3. **Object registry:** Add entry in `object_registry.rb`
4. **Services:** Call `Broadcaster.object_changed` after mutations
5. **Frontend types:** Add to `OBJECT_TYPES` and `ObjectTypeMap` in `types/pool.ts`
6. **Frontend store:** Create Pinia store that reads from the object pool
7. **Update this file:** Add the new type to the Object Types table above

## Code Style

**Backend (Ruby):**

- Every file: `# typed: true` and `# frozen_string_literal: true`
- Double quotes for strings
- Roda routes use `hash_routes` plugin pattern
- Models are immutable `T::Struct` — `from_row` class method, `to_api_hash` instance method
- Services return `Result` monads, never raise for expected errors
- RuboCop enforced; use `not_to` (not `to_not`) in RSpec

**Frontend (TypeScript/Vue):**

- `<script setup lang="ts">` syntax
- Tailwind CSS for all styling with `dark:` prefix for dark mode
- Composables for shared state/logic
- Stores call API, then auto-import pool objects from response
- No semicolons (Prettier-enforced)

## Keeping Documentation Current

When making changes, update:

- **This file (CLAUDE.md)** — API endpoints, database schema, object types, architectural patterns
- **README.md** — Features, setup instructions, high-level architecture
- **doc/real-time-sync.md** — WebSocket protocol, broadcast flow, pool merge logic
- **doc/workspaces.md** — Workspace model, authorization, switching flow

If you add a new route, model, service pattern, or change the data model, reflect it here so future sessions have accurate context.
