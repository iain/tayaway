# Tayaway

An event planning web application with magic link authentication and flexible date range scheduling.

## Features

- **Magic link authentication** - Passwordless email-based login
- **Event management** - Create, edit, and delete events
- **Flexible date ranges** - Assign multiple date ranges per event (e.g., "week 1, week 3")
- **User profiles** - View and manage account information
- **Dark mode** - Toggle between light and dark themes

## Tech Stack

- **Frontend**: Vue 3, TypeScript, Vite, Tailwind CSS
- **Backend**: Ruby, Roda, Sequel, PostgreSQL
- **Testing**: Vitest (frontend), RSpec (backend), Playwright (e2e)
- **Tools**: mise, pnpm, Sorbet (Ruby types)

## Prerequisites

- [mise](https://mise.jdx.dev/) - manages Ruby, Node.js, and pnpm
- PostgreSQL

## Setup

```bash
mise install
pnpm install
cd backend && bundle install && cd ..
mise run db_create
mise run db_migrate
```

## Development

```bash
mise run dev
```

- Frontend: http://localhost:5173
- Backend: http://localhost:9292

In development, magic link URLs are printed to the backend console.

## Testing

```bash
mise run test              # all tests
mise run test_frontend     # frontend unit tests
mise run test_backend      # backend specs
mise run test_e2e          # playwright e2e tests
```

## Other Commands

```bash
mise run lint              # run linters (ESLint + Rubocop)
mise run typecheck         # run type checkers (vue-tsc + Sorbet)
mise run build             # build for production
mise run db_reset          # drop, create, and migrate database
```

## Project Structure

```
frontend/          Vue 3 SPA
  └── src/pages/       Page components
  └── src/components/  Reusable UI components
  └── src/composables/ Shared state and logic

backend/           Ruby API
  └── app/routes/      API endpoints
  └── app/models/      Sequel models
  └── db/migrations/   Database migrations

e2e/               Playwright tests
```
