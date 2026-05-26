## `audit`

- Depends: //...:audit

- **Usage**: `audit`

Dependency vulnerability scanning

## `build`

- Depends: //frontend:build

- **Usage**: `build`

Build production frontend assets

## `check`

- Depends: //...:lint, //...:typecheck, //...:test, //...:audit, check:cache-version

- **Usage**: `check`
- **Aliases**: `c`

Full local validation: lint, typecheck, test, audit, cache-version (no e2e)

## `check:cache-version`

- **Usage**: `check:cache-version`

Verify CACHE_VERSION is bumped when pool-cache schema changes

## `ci`

- Depends: check, e2e

- **Usage**: `ci`

Full CI: check + e2e

## `ci:fresh`

- **Usage**: `ci:fresh`

Wipe local daemon/cache/DB state, then run full CI

## `console`

- Depends: //backend:console

- **Usage**: `console`

Open a Ruby console with the app loaded

## `containers:down`

- **Usage**: `containers:down [--keep-data]`

Tear down the local podman/compose stack and drop its volumes

### Flags

#### `--keep-data`

Preserve the db and geoip volumes

## `containers:up`

- **Usage**: `containers:up`

Build and start the local podman/compose stack against the current toolchain image

## `db:backup`

- Depends: //backend:db:backup

- **Usage**: `db:backup`

Trigger a database backup on the production server

## `db:create`

- Depends: //backend:db:create

- **Usage**: `db:create`

Create the development database

## `db:drop`

- Depends: //backend:db:drop

- **Usage**: `db:drop`

Drop the development database

## `db:migrate`

- Depends: //backend:db:migrate

- **Usage**: `db:migrate`

Run database migrations

## `db:reset`

- Depends: //backend:db:reset

- **Usage**: `db:reset`

Reset the development database

## `db:rollback`

- Depends: //backend:db:rollback

- **Usage**: `db:rollback`

Rollback the last migration

## `db:seed`

- Depends: //backend:db:seed

- **Usage**: `db:seed`

Seed the development database

## `db:seed-dev`

- Depends: //backend:db:seed-dev

- **Usage**: `db:seed-dev`

Populate the development database with rich sample data

## `deploy`

- **Usage**: `deploy <host> [sha]`

Deploy a git SHA to a host: pull images, restart, smoke-test /health, auto-rollback

### Arguments

#### `<host>`

ssh target, e.g. tayaway@new.tayaway.nl

#### `[sha]`

git SHA to deploy (default: HEAD)

## `dev`

- Depends: //backend:dev, //frontend:dev

- **Usage**: `dev`
- **Aliases**: `d`

Start frontend + backend dev servers

## `dev:reset`

- Depends: //backend:dev:reset

- **Usage**: `dev:reset`

Kill any falcon-host / fsevent_watch processes left holding the dev backend port

## `docs:tasks`

- **Usage**: `docs:tasks`

Regenerate TASKS.md from mise task descriptions and usage specs

## `e2e`

- Depends: //backend:db:setup-e2e

- **Usage**: `e2e`

Playwright end-to-end tests — extra args pass through to playwright

## `e2e:reset`

- **Usage**: `e2e:reset`

Kill any falcon / vite / fsevent_watch processes left holding the e2e ports

## `e2e:snapshots:update`

- **Usage**: `e2e:snapshots:update`

Trigger the GitHub workflow that regenerates Playwright visual baselines on Linux and commits them back

## `lint`

- Depends: //...:lint, lint:config, docs:tasks

- **Usage**: `lint`

Lint all code (autofix locally; report-only when $CI is set)

## `lint:config`

- **Usage**: `lint:config`

Canonically format all mise.toml files

## `precommit`

- Depends: lint, check:cache-version

- **Usage**: `precommit`

Pre-commit hook: fast formatters only (lint + cache-version). Full validation lives in `check` and CI.

## `setup`

- Depends: setup:deps, setup:db, setup:hooks, //backend:data:geoip

- **Usage**: `setup`

Set up the project after cloning

## `setup:db`

- Depends: //backend:setup:db

- **Usage**: `setup:db`

Create and migrate the development, test, and e2e databases

## `setup:deps`

- Depends: //...:setup:deps, setup:deps-root

- **Usage**: `setup:deps`

Install all dependencies

## `setup:deps-root`

- **Usage**: `setup:deps-root`

Install root dependencies (Capistrano, Playwright, prettier)

## `setup:hooks`

- **Usage**: `setup:hooks`

Install the git pre-commit hook

## `test`

- Depends: //...:test

- **Usage**: `test`
- **Aliases**: `t`

Run unit and integration tests

## `toolchain:tag`

- **Usage**: `toolchain:tag`

Print the content hash of the toolchain inputs — used as the GHCR tag

## `tools:upgrade`

- **Usage**: `tools:upgrade`

Bump every config_root's tool versions to the latest available

## `typecheck`

- Depends: //...:typecheck

- **Usage**: `typecheck`

Run all type checkers

## `vm:provision`

- **Usage**: `vm:provision <host>`

Idempotent app-side provisioning on a freshly-cloud-inited VM — drops quadlet units, daemon-reloads, pre-pulls images

### Arguments

#### `<host>`

ssh target, e.g. tayaway@new.tayaway.nl
