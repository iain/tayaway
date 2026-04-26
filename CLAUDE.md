# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Tayaway is a real-time collaborative event planning app. Ruby 4 / Roda backend, Vue 3 / TypeScript 6 frontend, PostgreSQL database with LISTEN/NOTIFY for real-time sync.

## Commands

All commands use `mise run`. Key ones:

| Task        | Command                                         |
| ----------- | ----------------------------------------------- |
| Dev servers | `mise run dev` (backend :9292, frontend :5173)  |
| All checks  | `mise run check` (lint, typecheck, test, audit) |
| Full CI     | `mise run ci` (check + e2e)                     |
| Lint        | `mise run lint`                                 |
| Typecheck   | `mise run typecheck`                            |
| Tests       | `mise run test`                                 |
| E2E         | `mise run e2e`                                  |
| DB migrate  | `mise run db:migrate`                           |
| DB reset    | `mise run db:reset`                             |
| Console     | `mise run console`                              |
| Build       | `mise run build`                                |

**Single test:**

```
cd backend && bundle exec rspec spec/path/to/spec.rb
cd frontend && pnpm exec vitest run src/path/to/file.spec.ts
```

## Architecture

### Backend (`backend/`)

- **Framework**: Roda 3 with `hash_routes` plugin, served by Falcon (fiber-based)
- **ORM**: Sequel 5 with PostgreSQL
- **Models** (`app/models/`): Immutable plain Ruby classes with keyword `initialize`, factory class methods for queries, and `to_api_hash` for serialization
- **Services** (`app/services/`): Return `Result[Success, ServiceError]` monad. Entry point is `.call()`. Chain with `.bind()` (see "Backend code conventions" below for chain shape)
- **Routes** (`app/routes/`): Roda hash_routes organized by domain. Auth via session cookies, CSRF via `X-CSRF-Protection: 1` header
- **Serializers** (`app/serializers/`): `PoolSerializer` normalizes all objects into a flat pool format `{ objects: [{ id, objectType, ...fields }] }`
- **WebSocket** (`app/websocket/`): PostgreSQL NOTIFY → Listener thread → broadcasts serialized objects to connected clients
- **Object Registry** (`app/object_registry.rb`): Central registry mapping object types to their models/serializers

### Frontend (`frontend/`)

- **Framework**: Vue 3.5 with `<script setup lang="ts">`, Pinia stores, Vue Router
- **Build**: Vite 7, Tailwind CSS 4, PWA via `vite-plugin-pwa`
- **Central store** (`src/stores/objectPool.ts`): Normalized object pool — all entities merged here, timestamp-based conflict resolution (newer wins)
- **WebSocket store** (`src/stores/websocket.ts`): Connection management, full/partial sync coordination, reconnection
- **Command queue** (`src/stores/commandQueue.ts`): Offline mutation queue persisted to IndexedDB
- **API client** (`src/api/client.ts`): Exports two entry points. `api.get` is pool-aware — responses automatically hydrate the object pool via `processPoolResponse`. `rawApi` is the pure, low-level client used only by auth/session/invite/ws-ticket flows and internally by the command queue; it does **not** hydrate the pool. **Mutations must flow through `useMutation` so they participate in the offline command queue** — `api` deliberately does not expose `post/put/patch/delete` to make this hard to bypass. If you truly need a non-queued mutation (e.g. auth), use `rawApi` explicitly
- **Composables** (`src/composables/`): `useMutation` (create/update/destroy with optimistic updates), `useHydratedEvent`, `useCalendar`, etc.
- **Persistence** (`src/api/poolDb.ts`): IndexedDB cache for instant startup before WebSocket connects

### Real-Time Sync Flow

1. Service mutates DB → calls `Broadcaster.object_changed`
2. PostgreSQL NOTIFY triggers backend Listener thread
3. Listener fetches full object, serializes via PoolSerializer, broadcasts to WebSocket clients
4. Clients merge into local object pool (strictly newer `updatedAt` wins)
5. Optimistic updates are tracked as pending until server confirms

### E2E Tests (`e2e/`)

Playwright tests run against separate servers (backend :9293, frontend :5174) with a dedicated `tayaway_e2e` database.

## Backend code conventions

- **Module singletons**: Define singleton methods inside `class << self`. Don't use `module_function` — it duplicates each method as both a module-level and a private instance method, which obscures intent and breaks cleanly with `private` for helpers.
- **`Result` chains**: Start chains with a bare `Success()` and put every step (including the first lookup) inside a `.bind { … }` block. Every step then reads as a uniform link in the chain — easier to reorder, insert steps, or skim — instead of having one bare leading call followed by `.bind`s.

  ```ruby
  Success()
    .bind { Foo.find_result(id) }
    .bind { |foo| FooPolicy.enforce(:do_thing, foo, membership: membership) }
    .bind { |foo| do_thing(foo) }
  ```

## Migration Safety

Migrations run **before** the app restarts during deploy — old code is still serving traffic. All migrations must be **additive**. Destructive changes (drop column/table, rename, add NOT NULL) require a two-deploy pattern. See `doc/database-migrations.md` for details.

## Commits and PRs

- **Commit messages**: Free-form imperative subject (e.g. "Fix request body consumption in rate limiter"). No conventional commit prefixes. Always explain _why_ in the body unless the change is truly trivial. Don't list what changed unless it's not obvious from the diff.
- **PRs**: Default to draft. Body should be minimal and focused on _why_, no headers or sections, no test plan. We squash-merge to keep main clean, so write the PR title+body as if it will become the final commit message. Always base the description on the actual diff against the base branch (`git diff main...HEAD`), not on individual commit messages — intermediate work that was later reverted should not appear in the description.
- **No trailers or footers** — no "Generated with Claude Code", no Co-Authored-By.
- **Cohesive commits**: Split unrelated changes into separate commits, but don't over-split. Use judgement.
- **Don't push to main** without asking first.

## Environment

- Required env vars: `DATABASE_URL`, `APP_SECRET`, `FRONTEND_URL`
- Config loaded from `backend/.env.{development,test,e2e}` via dotenv (not in production)
- Three databases: `tayaway_development`, `tayaway_test`, `tayaway_e2e`
