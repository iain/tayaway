# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Tayaway is a real-time collaborative event planning app. Ruby 4 / Roda backend, Vue 3 / TypeScript 6 frontend, PostgreSQL database with LISTEN/NOTIFY for real-time sync.

## Commands

All commands use `mise run`. The most-used:

| Task        | Command                                         |
| ----------- | ----------------------------------------------- |
| Dev servers | `mise run dev` (backend :9292, frontend :5173)  |
| All checks  | `mise run check` (lint, typecheck, test, audit) |
| Full CI     | `mise run ci` (check + e2e)                     |
| DB reset    | `mise run db:reset`                             |
| Console     | `mise run console`                              |

Run `mise tasks ls --all` for the full task surface.

## Architecture

### Backend (`backend/`)

- **Framework**: Roda 3 with `hash_routes` plugin, served by Falcon (fiber-based)
- **ORM**: Sequel 5 with PostgreSQL
- **Models** (`app/models/`): Immutable plain Ruby classes with keyword `initialize`, factory class methods for queries, and `to_api_hash` for serialization
- **Services** (`app/services/`): Return `Result[Success, ServiceError]` monad. Entry point is `.call()`. Chain with `.bind()` (see "Code conventions" below for chain shape)
- **Routes** (`app/routes/`): Roda hash_routes organized by domain. Auth via session cookies, CSRF via `X-CSRF-Protection: 1` header
- **Serializers** (`app/serializers/`): `PoolSerializer` normalizes all objects into a flat pool format `{ objects: [{ id, objectType, ...fields }] }`
- **WebSocket** (`app/websocket/`): PostgreSQL NOTIFY → per-worker Listener fiber → broadcasts serialized objects to connected clients
- **Object Registry** (`app/object_registry.rb`): Central registry mapping object types to their models/serializers
- **Admin site** (`admin/`): Operator-only maintenance dashboard — separate Roda app and process, mTLS at the edge. See `doc/admin.md`

### Frontend (`frontend/`)

- **Framework**: Vue 3.5 with `<script setup lang="ts">`, Pinia stores, Vue Router
- **Build**: Vite 8, Tailwind CSS 4, PWA via `vite-plugin-pwa`
- **Central store** (`src/stores/objectPool.ts`): Normalized object pool — all entities merged here, timestamp-based conflict resolution (newer wins)
- **WebSocket store** (`src/stores/websocket.ts`): Connection management, full/partial sync coordination, reconnection
- **Command queue** (`src/stores/commandQueue.ts`): Offline mutation queue persisted to IndexedDB
- **API client** (`src/api/client.ts`): Exports two entry points. `api.get` is pool-aware — responses automatically hydrate the object pool via `processPoolResponse`. `rawApi` is the pure, low-level client used only by auth/session/invite/ws-ticket flows and internally by the command queue; it does **not** hydrate the pool. **Mutations must flow through `useMutation` so they participate in the offline command queue** — `api` deliberately does not expose `post/put/patch/delete` to make this hard to bypass. If you truly need a non-queued mutation (e.g. auth), use `rawApi` explicitly
- **Composables** (`src/composables/`): `useMutation` (create/update/destroy with optimistic updates), `useHydratedEvent`, `useCalendar`, etc.
- **Persistence** (`src/api/poolDb.ts`): IndexedDB cache for instant startup before WebSocket connects

### Real-Time Sync Flow

1. Service mutates DB → calls `Broadcaster.object_changed`
2. PostgreSQL NOTIFY wakes the per-worker Listener fiber
3. Listener fetches full object, serializes via PoolSerializer, broadcasts to WebSocket clients
4. Clients merge into local object pool (strictly newer `updatedAt` wins)
5. Optimistic updates are tracked as pending until server confirms

## Testing

### Running tests

```
mise run '//backend:test' spec/path/to/spec.rb
cd frontend && aube exec vitest run src/path/to/file.spec.ts
```

Backend specs must go through the mise task — it re-enters mise with `MISE_ENV=test` so `.env.test` (and the `tayaway_test` database) get loaded. A bare `bundle exec rspec` inherits the development `DATABASE_URL` from the shell; `spec_helper.rb` aborts in that case before DatabaseCleaner can truncate the wrong database.

**Typecheck note:** use `mise run typecheck` (or `aube exec vue-tsc -b`). `vue-tsc --noEmit` is **not** equivalent — it can pass while project-references mode finds real errors, particularly in `*.spec.ts` files with their own factories.

### E2E setup

Playwright tests live in `e2e/` and run against separate servers (backend :9293, frontend :5174) with a dedicated `tayaway_e2e` database.

For big new features, drive development with a failing Playwright test that captures the user-visible flow, then iterate inner-loop unit tests against the layers it touches. The e2e test stays red while the inner tests come up green one by one.

## Code conventions

- **`if/elsif/else` over guard clauses**: Express branching with regular `if/elsif/else` blocks. Reserve early-return guard clauses for actual input-invariant guards at the top of a method (e.g. a nil-check on a required argument). Don't reach for guard clauses just to flatten a method — explicit branches read better and keep all outcomes visible together. When a method grows into a *longer run of fallible steps* (a sequence of lookups, a check, then the work), that's no longer a guard situation — express it as a `Result` chain (backend; see **`Result` chains** below) rather than a stack of `return unless`/`return if`.

### Backend

- **Authorization**: see `doc/authorization.md` before changing any policy, adding policy actions, or touching `frontend/src/composables/usePermission.ts`.
- **Module singletons**: Define singleton methods inside `class << self`. Don't use `module_function` — it duplicates each method as both a module-level and a private instance method, which obscures intent and breaks cleanly with `private` for helpers.
- **`Result` chains**: Start chains with a bare `Success()` and put every step (including the first lookup) inside a `.bind { … }` block. Every step then reads as a uniform link in the chain — easier to reorder, insert steps, or skim — instead of having one bare leading call followed by `.bind`s.

  ```ruby
  Success()
    .bind { Foo.find_result(id) }
    .bind { |foo| FooPolicy.enforce(:do_thing, foo, membership: membership) }
    .bind { |foo| do_thing(foo) }
  ```

  **When to reach for one** (the long-form counterpart to the guard-clause rule above): any method that threads through several fallible steps. A growing stack of `return unless`/`return if` over required lookups is the smell — lift it into a chain, one `Model.find_result(id)` per lookup and a `.bind` returning `Success`/`Failure` per predicate. Carry state forward in the bound value (a small hash when a later step needs more than one earlier result). This holds even for fire-and-forget flows whose result is discarded — a background job that only needs to no-op — since the discarded `Failure` *is* the early-out (see `ChoreRosters::SendReminder`).

## Migration Safety

Migrations run **before** the app restarts during deploy — old code is still serving traffic. All migrations must be **additive**. Destructive changes (drop column/table, rename, add NOT NULL) require a two-deploy pattern. See `doc/database-migrations.md` for details.

The same additive discipline applies to the client↔server API: deployed PWA clients keep running cached bundles after a deploy. Breaking API changes ship behind the protocol version gate (`PROTOCOL_VERSION` / `ClientProtocol::MIN_SUPPORTED_VERSION`) — see `doc/protocol-versioning.md` before removing or reshaping anything a client calls.

## Commits and PRs

This repo uses **Conventional Commits**: the subject starts with a type — `feat:`, `fix:`, `docs:`, `perf:`, `refactor:`, `chore:`, `ci:`, etc. — optionally scoped (`feat(dashboard): …`), with a trailing `!` or a `BREAKING CHANGE:` footer for breaking changes. This **overrides the global "no conventional-commit prefixes" preference** for this repo, because `CHANGELOG.md` is generated from commit history by git-cliff (`mise run changelog`; grouping and skip rules live in `cliff.toml`). The rest of the global commit conventions still hold — imperative subject, a body only to explain *why*, no trailers.

We squash-merge to `main`, so the **PR title** becomes the squashed commit subject and must itself be a valid Conventional Commit; the body should read as that commit's body.

Don't push to `main` without asking first.

## Environment

- Required env vars: `DATABASE_URL`, `APP_SECRET`, `FRONTEND_URL`
- Config loaded from `backend/.env.{development,test,e2e,production}` by mise (`_.file` in `backend/mise.toml`), keyed off `MISE_ENV`. Production additionally loads `backend/.env.production.yaml` for secrets; mise silently skips the yaml in non-prod envs. Neither production file is in this repo — their source of truth is `vps/env/` in the private infra repo, and the quadlet bind-mounts them into the container at these paths at runtime (see that repo's `provision.sh`). `backend/.env.example` is the schema doc for what's expected. Tasks that need a non-default env wrap themselves with `mise --env=<env> exec -- …`. Production: systemd sets `MISE_ENV=production`; `ExecStart` goes through `mise exec`. No dotenv at runtime.
- Three databases: `tayaway_development`, `tayaway_test`, `tayaway_e2e`
