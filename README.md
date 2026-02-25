# Tayaway

A real-time collaborative event planning app. Create events, propose date ranges, vote on the best time, track expenses, and manage task lists — all synced live across devices.

## Features

- **Magic link authentication** — Passwordless email login with session management
- **Workspaces** — Organize events by team or group; invite members by email with role-based access (owner/admin/member)
- **Date polls** — Create polls with multiple date range options, set deadlines, and resolve a winner
- **Live voting** — Vote yes/no/preferably not on each proposed date, with instant results
- **RSVPs** — Confirm attendance with custom date ranges once event dates are set
- **Expense tracking** — Log event expenses and split costs by nights attended
- **Task lists** — Workspace-scoped task lists with drag-and-drop reordering and vim-style keyboard navigation
- **ICS export** — Download `.ics` calendar files for events
- **Command palette** — Cmd+K to search, navigate, and take actions
- **Real-time sync** — All changes broadcast instantly to connected clients via WebSockets + PostgreSQL LISTEN/NOTIFY
- **Offline support** — IndexedDB-backed command queue replays mutations on reconnect; pool cache for instant startup
- **PWA** — Installable progressive web app with service worker caching and auto-update detection
- **Dark mode** — System-aware light/dark theme with manual toggle
- **Dashboard** — Polls needing attention, events needing RSVP, and currently happening events at a glance

## Tech Stack

| Layer     | Technologies                                                 |
| --------- | ------------------------------------------------------------ |
| Frontend  | Vue 3.5, TypeScript 5.9, Vite 7, Tailwind CSS 4, Pinia 3     |
| Backend   | Ruby 4.0, Roda 3, Sequel 5, Sorbet                           |
| Database  | PostgreSQL 18 (LISTEN/NOTIFY for real-time)                  |
| WebSocket | roda-websockets, Falcon                                      |
| Testing   | Vitest (frontend), RSpec (backend), Playwright (e2e)         |
| Deploy    | Capistrano, Nginx, systemd                                   |
| Tooling   | mise, pnpm 10, Husky, lint-staged, ESLint, RuboCop, Prettier |

## Prerequisites

- [mise](https://mise.jdx.dev/) — manages Ruby, Node.js, pnpm, and PostgreSQL versions
- PostgreSQL 18+

## Setup

```bash
# Install runtimes (Ruby 4.0.1, Node 24, pnpm 10)
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
mise run dev              # Start frontend (5173) + backend (9292)
mise run ci               # All CI checks (lint, typecheck, tests, e2e) in parallel
mise run test             # All tests (frontend + backend + e2e)
mise run test_backend     # RSpec tests only
mise run test_frontend    # Vitest tests only
mise run test_e2e         # Playwright e2e tests (requires dev server)
mise run lint             # ESLint + RuboCop
mise run typecheck        # vue-tsc + Sorbet
mise run build            # Production build
mise run deploy           # Deploy to production (cap production deploy)
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
│       ├── pages/         Route components (Home, Events, Tasks, Profile, Members, ...)
│       ├── layouts/       AuthenticatedLayout (navbar, connection badge, command palette)
│       ├── components/    Reusable UI (events/, calendar/, votes/, tasks/, expenses/, form/)
│       ├── composables/   Shared logic (useHydratedEvent, useCalendar, useMutation, useDarkMode)
│       ├── stores/        Pinia stores (objectPool, websocket, commandQueue, auth, ...)
│       └── types/         TypeScript type definitions and object pool registry
│
├── backend/               Ruby API server
│   └── app/
│       ├── routes/        Roda hash_routes (auth, events, expenses, task_lists, members, ...)
│       ├── models/        Immutable Sorbet T::Struct models
│       ├── services/      Business logic with Result monad pattern
│       ├── serializers/   PoolSerializer for normalized API responses
│       └── websocket/     Listener, ConnectionManager, MessageHandler
│
├── e2e/                   Playwright end-to-end tests
├── doc/                   Architecture documentation
└── config/                Capistrano deployment configuration
```

### Real-Time Sync

The app uses a normalized **object pool** pattern for state management:

1. Backend services mutate the database and call `Broadcaster.object_changed`
2. PostgreSQL `NOTIFY` triggers a background `Listener` thread
3. Listener fetches the full object, serializes it, and broadcasts via WebSocket
4. All connected clients merge the update into their local object pool (newer timestamp wins)
5. Vue reactivity re-renders affected components automatically
6. On reconnect, partial sync via `since=<timestamp>` fetches only changed objects

See [`doc/real-time-sync.md`](doc/real-time-sync.md) for the full architecture.

### Data Model

```
Workspace
  ├── Event
  │     ├── DatePoll (open → expired → resolved)
  │     │     └── DateRange
  │     │           └── Vote (yes / no / preferably_not)
  │     ├── Rsvp (attending + custom date range)
  │     └── Expense (amount + description)
  └── TaskList
        └── TaskItem
```

Users belong to workspaces through memberships (owner/admin/member roles). All domain data is workspace-scoped.

See [`doc/workspaces.md`](doc/workspaces.md) for workspace switching and authorization details.

### Deployment

Production deploys via Capistrano to localhost over SSH. Falcon runs as a systemd service behind Nginx, which serves static frontend assets and proxies API/WebSocket requests.

## License

Private — all rights reserved.
