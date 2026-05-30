# Getting Started

## Prerequisites

- [mise](https://mise.jdx.dev/) — manages Ruby, Node.js, and aube versions
- PostgreSQL 18+
- `libmaxminddb` — needed to build the `mmdb` gem's native extension (`brew install libmaxminddb` on macOS)

## Setup

```bash
# Install runtimes (Ruby 4, Node 26, aube)
mise install
```

The default `DATABASE_URL` connects as a `tayaway` Postgres role, which won't exist on a fresh install. Create it with `CREATEDB` so the setup task can create the per-env databases:

```bash
createuser --createdb tayaway
```

```bash
# Install dependencies, generate dotenv files, and set up databases
mise run setup
```

This installs frontend (aube) and backend (bundler) dependencies, generates `backend/.env.development` (and `.env.test`) from `backend/.env.example` with a fresh `APP_SECRET`, then creates and migrates all three databases (development, test, e2e). Edit `backend/.env.development` afterwards if you need non-default settings (custom DB URL, SMTP for outgoing email, etc.) — uncommented lines are required, commented lines show optional overrides with their defaults.

If the `mmdb` gem fails to build with `'maxminddb.h' file not found`, Homebrew's `libmaxminddb` is keg-installed and isn't on mkmf's default search path. Point bundler at it once:

```bash
cd backend && bundle config set build.mmdb --with-opt-dir=$(brew --prefix libmaxminddb)
```

### Git hooks

Pre-commit linting is managed by [hk](https://hk.jdx.dev) (config in `hk.pkl`). `mise run setup` installs hooks for this clone automatically. The recommended once-per-machine setup is to install hooks globally so every repo picks them up (repos without an `hk.pkl` are a no-op):

```bash
hk install --global   # requires Git 2.54+
```

## Development

```bash
mise run dev
```

- Frontend: http://localhost:5173
- Backend API: http://localhost:9292

The frontend dev server proxies `/api/*` requests to the backend. Login link URLs are printed to the backend console.

## Useful Commands

```bash
mise run check            # Lint (autofix), typecheck, test, audit — no e2e
mise run ci               # check + Playwright e2e
mise run test             # Frontend + backend tests
mise run test:frontend    # Vitest only
mise run test:backend     # RSpec only
mise run test:e2e         # Playwright e2e tests
mise run lint             # hk: RuboCop, ESLint, mise fmt, cache-version
mise run typecheck        # vue-tsc + Sorbet
mise run console          # Ruby console with app loaded
mise run db:migrate       # Run pending migrations
mise run db:reset         # Drop, create, and migrate database
```

Run a single test:

```bash
cd backend && bundle exec rspec spec/path/to/spec.rb
cd frontend && aube exec vitest run src/path/to/file.spec.ts
```

### Visual snapshot tests

The Playwright suite includes one visual-regression spec (`e2e/tests/design-system.spec.ts`). Only the Linux baselines that CI generates are tracked in git; `*-darwin.png` and `*-win32.png` are gitignored. On your first local e2e run the test fails and writes the actual screenshot as the new local baseline — re-run and it'll pass. To refresh the local baseline after intentional design changes, use `mise run e2e -- design-system --update-snapshots`. To refresh the Linux baselines that CI compares against, use `mise run e2e:snapshots:update` (runs the regen workflow on GitHub Actions).

## Devcontainer (experimental)

An alternative to local setup — a devcontainer with all dependencies pre-configured.

```bash
# Start Claude Code in the devcontainer
.devcontainer/claude.sh

# Run any command
.devcontainer/exec.sh mise run check
.devcontainer/exec.sh mise run dev
.devcontainer/exec.sh bash
```

`.devcontainer/claude.sh` starts the container (if needed), pulls your OAuth token from macOS Keychain, and launches Claude Code with `--dangerously-skip-permissions`. Extra args are forwarded: `.devcontainer/claude.sh -p "fix the login bug"`.
