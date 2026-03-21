# Tayaway

A real-time collaborative event planning app. Create events, propose date ranges, vote on the best time, track expenses, and manage task lists — all synced live across devices.

## Features

- **Login link authentication** — Passwordless email login with session management
- **Workspaces** — Organize events by team or group; invite members by email with role-based access (owner/admin/member)
- **Date polls** — Create polls with multiple date range options, set deadlines, and resolve a winner
- **Live voting** — Vote yes/no/preferably not on each proposed date, with instant results
- **RSVPs** — Confirm attendance with custom date ranges once event dates are set
- **Expense tracking** — Log event expenses and split costs by nights attended
- **Chore rosters** — Assign daily chores fairly with pinning and autofill
- **Task lists** — Workspace-scoped task lists with drag-and-drop reordering and vim-style keyboard navigation
- **Settlements** — Calculate minimal transfers to settle up; EPC QR codes for easy payment
- **ICS export** — Download `.ics` calendar files for events
- **Command palette** — Cmd+K to search, navigate, and take actions
- **Real-time sync** — All changes broadcast instantly via WebSockets + PostgreSQL LISTEN/NOTIFY
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

## Getting Started

See [`GETTING_STARTED.md`](GETTING_STARTED.md) for local setup instructions.

### Devcontainer

The project includes a devcontainer for a fully isolated development environment with all dependencies pre-configured.

**Start Claude Code in the devcontainer:**

```bash
.devcontainer/claude.sh
```

This starts the devcontainer (if not already running), pulls your OAuth token from macOS Keychain, and launches Claude Code with `--dangerously-skip-permissions`. Extra args are forwarded: `.devcontainer/claude.sh -p "fix the login bug"`.

**Run any command in the devcontainer:**

```bash
.devcontainer/exec.sh mise run fix
.devcontainer/exec.sh mise run serve
.devcontainer/exec.sh bash
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
├── doc/                   Architecture docs (offline-support.md)
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


### Data Model

```
Workspace
  ├── Event
  │     ├── DatePoll (open → expired → resolved)
  │     │     └── DateRange
  │     │           └── Vote (yes / no / preferably_not)
  │     ├── Rsvp (attending + custom date range)
  │     ├── Expense (amount + description)
  │     ├── Settlement → SettlementTransfer
  │     └── ChoreRoster → Chore → ChoreAssignment
  └── TaskList
        └── TaskItem
```

Users belong to workspaces through memberships (owner/admin/member roles). All domain data is workspace-scoped.

### Deployment

Production deploys via Capistrano to localhost over SSH. Falcon runs as a systemd service behind Nginx, which serves static frontend assets and proxies API/WebSocket requests.

## License

Private — all rights reserved.
