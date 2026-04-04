# Getting Started

## Prerequisites

- [mise](https://mise.jdx.dev/) — manages Ruby, Node.js, and pnpm versions
- PostgreSQL 18+

## Setup

```bash
# Install runtimes (Ruby 4.0.1, Node 24, pnpm 10)
mise install

# Configure environment
cp backend/.env.example backend/.env.development
```

Edit `backend/.env.development`:

- Set `DATABASE_URL` to your PostgreSQL connection string
- Generate `APP_SECRET` with: `ruby -e "require 'securerandom'; puts SecureRandom.base64(32)"`
- Configure SMTP settings if you want emails sent (in development, login links are printed to the console instead)

```bash
# Install dependencies and set up databases
mise run setup
```

This installs frontend (pnpm) and backend (bundler) dependencies, then creates and migrates all three databases (development, test, e2e).

## Development

```bash
mise run dev
```

- Frontend: http://localhost:5173
- Backend API: http://localhost:9292

The frontend dev server proxies `/api/*` requests to the backend. Login link URLs are printed to the backend console.

## Useful Commands

```bash
mise run fix              # All CI checks, auto-fixing lint issues where possible
mise run ci               # All CI checks without auto-fix
mise run test             # Frontend + backend tests
mise run test:frontend    # Vitest only
mise run test:backend     # RSpec only
mise run test:e2e         # Playwright e2e tests
mise run lint             # ESLint + RuboCop
mise run typecheck        # vue-tsc + Sorbet
mise run console          # Ruby console with app loaded
mise run db:migrate       # Run pending migrations
mise run db:reset         # Drop, create, and migrate database
```

Run a single test:

```bash
cd backend && bundle exec rspec spec/path/to/spec.rb
cd frontend && pnpm exec vitest run src/path/to/file.spec.ts
```

## Devcontainer (experimental)

An alternative to local setup — a devcontainer with all dependencies pre-configured.

```bash
# Start Claude Code in the devcontainer
.devcontainer/claude.sh

# Run any command
.devcontainer/exec.sh mise run fix
.devcontainer/exec.sh mise run dev
.devcontainer/exec.sh bash
```

`.devcontainer/claude.sh` starts the container (if needed), pulls your OAuth token from macOS Keychain, and launches Claude Code with `--dangerously-skip-permissions`. Extra args are forwarded: `.devcontainer/claude.sh -p "fix the login bug"`.
