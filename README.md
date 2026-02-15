# Tayaway

A real-time collaborative event planning app. Create events, propose date ranges, and vote on the best time — all synced live across devices.

## Features

- **Magic link authentication** — Passwordless email login (no passwords to remember)
- **Workspaces** — Organize events by team or group; invite members by email
- **Date polls** — Create polls with multiple date range options, set deadlines, and resolve a winner
- **Live voting** — Vote yes/no/preferably not on each proposed date, with instant results
- **Real-time sync** — All changes broadcast instantly to connected clients via WebSockets
- **Offline support** — Queued mutations replay automatically when back online (IndexedDB-backed)
- **PWA** — Installable as a progressive web app with service worker caching
- **Dark mode** — System-aware light/dark theme

## Tech Stack

| Layer     | Technologies                                              |
| --------- | --------------------------------------------------------- |
| Frontend  | Vue 3, TypeScript, Vite, Tailwind CSS, Pinia              |
| Backend   | Ruby 4, Roda, Sequel, Sorbet                              |
| Database  | PostgreSQL (LISTEN/NOTIFY for real-time)                  |
| WebSocket | roda-websockets, Falcon server                            |
| Testing   | Vitest (frontend), RSpec (backend), Playwright (e2e)      |
| Tooling   | mise, pnpm, Husky, lint-staged, ESLint, RuboCop, Prettier |

## Prerequisites

- [mise](https://mise.jdx.dev/) — manages Ruby, Node.js, and pnpm versions
- PostgreSQL 12+

## Setup

```bash
# Install runtimes (Ruby 4.0.1, Node 24, pnpm 9)
mise install

# Install dependencies
pnpm install
cd backend && bundle install && cd ..

# Create and configure the database
cp backend/.env.example backend/.env.development
# Edit backend/.env.development — set APP_SECRET and DATABASE_URL

mise run db_create
mise run db_migrate
```

## Development

```bash
mise run dev
```

- Frontend: http://localhost:5173
- Backend API: http://localhost:9292

The frontend dev server proxies `/api/*` requests to the backend. In development, magic link URLs are printed to the backend console instead of being emailed.

## Commands

All commands run through mise:

```bash
mise run dev              # Start frontend + backend
mise run test             # All tests (frontend + backend + e2e)
mise run test_backend     # RSpec tests only
mise run test_frontend    # Vitest tests only
mise run test_e2e         # Playwright e2e tests
mise run lint             # ESLint + RuboCop
mise run typecheck        # vue-tsc + Sorbet
mise run build            # Production build
mise run db_migrate       # Run pending migrations
mise run db_reset         # Drop, create, and migrate database
```

Run a single test:

```bash
cd backend && bundle exec rspec spec/path/to/spec.rb
cd frontend && pnpm exec vitest run src/path/to/file.spec.ts
```

## Architecture

```
tayaway/
├── frontend/              Vue 3 SPA (pnpm workspace)
│   └── src/
│       ├── api/           Fetch-based HTTP client + IndexedDB persistence
│       ├── pages/         Route components (Home, Events, Vote, Profile, Members)
│       ├── components/    Reusable UI (events/, calendar/, votes/, form/)
│       ├── composables/   Shared logic (useHydratedEvent, useCalendar, useMutation)
│       ├── stores/        Pinia stores (objectPool, websocket, commandQueue, auth, ...)
│       └── types/         TypeScript type definitions and object pool registry
│
├── backend/               Ruby API server
│   └── app/
│       ├── routes/        Roda hash_routes (auth, events, members, workspaces, ws)
│       ├── models/        Immutable Sorbet T::Struct models
│       ├── services/      Business logic with Result monad pattern
│       ├── serializers/   PoolSerializer for normalized API responses
│       └── websocket/     Listener, ConnectionManager, MessageHandler
│
├── e2e/                   Playwright end-to-end tests
└── doc/                   Architecture documentation
```

### Real-Time Sync

The app uses a normalized **object pool** pattern for state management:

1. Backend services mutate the database and call `Broadcaster.object_changed`
2. PostgreSQL `NOTIFY` triggers a background `Listener` thread
3. Listener fetches the full object, serializes it, and broadcasts via WebSocket
4. All connected clients merge the update into their local object pool
5. Vue reactivity re-renders affected components automatically

See [`doc/real-time-sync.md`](doc/real-time-sync.md) for the full architecture.

### Data Model

```
Workspace
  └── Event
        └── DatePoll (open → expired → resolved)
              └── DateRange
                    └── Vote (yes / no / preferably_not)
```

Users belong to workspaces through memberships (owner/admin/member roles). All domain data is workspace-scoped.

See [`doc/workspaces.md`](doc/workspaces.md) for workspace switching and authorization details.

## License

Private — all rights reserved.
