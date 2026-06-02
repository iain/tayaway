#!/usr/bin/env bash
# Brings the production images up as a local stack for the containerised e2e
# run, then leaves it running for Playwright (PLAYWRIGHT_BASE_URL=:8080).
#
# The trick that keeps it simple: db, web, and edge share ONE network namespace
# (docker --network container:<db>), so every service is reachable at
# `localhost` — exactly what the committed .env.e2e (DATABASE_URL=…@localhost)
# and the e2e harness (helpers.ts / global-setup.ts hardcode localhost:9293)
# already assume. No per-service DATABASE_URL/host rewriting.
#
# Ports are published on the db container because it owns the shared netns:
#   :8080 -> edge (Caddy)   — the Playwright baseURL
#   :9293 -> web  (Falcon)  — where the e2e harness POSTs /api/test/*
#
# No geoip container: GeoIP.lookup returns nil when the mmdb is absent, which
# is the documented test/CI behaviour (backend/lib/geo_ip.rb).
set -euo pipefail

BACKEND_IMAGE="${BACKEND_IMAGE:?set BACKEND_IMAGE}"
EDGE_IMAGE="${EDGE_IMAGE:?set EDGE_IMAGE}"
DB_IMAGE="${DB_IMAGE:?set DB_IMAGE}"
ENV_FILE="${ENV_FILE:?set ENV_FILE (path to .env.e2e to mount)}"

DB=tayaway-e2e-db
NETNS="container:${DB}"

log() { echo "▸ $*"; }

wait_for() { # <description> <command...>
  local desc="$1"
  shift
  for _ in $(seq 1 45); do
    if "$@" >/dev/null 2>&1; then
      log "$desc ready"
      return 0
    fi
    sleep 2
  done
  echo "✗ $desc never became ready" >&2
  return 1
}

log "starting db (owns the shared netns; publishes :8080 and :9293)"
docker run -d --name "$DB" \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=tayaway_e2e \
  -p 127.0.0.1:8080:8080 \
  -p 127.0.0.1:9293:9292 \
  "$DB_IMAGE"

wait_for "postgres" docker exec "$DB" pg_isready -U postgres -d tayaway_e2e

log "running migrations"
docker run --rm --network "$NETNS" \
  -e MISE_ENV=e2e \
  -v "$ENV_FILE":/app/backend/.env.e2e:ro \
  "$BACKEND_IMAGE" bundle exec rake db:migrate

# Production hardening (read-only rootfs + tmpfs /tmp) so the run exercises the
# same filesystem constraints as the web.container quadlet.
log "starting web (Falcon, read-only rootfs)"
docker run -d --name tayaway-e2e-web --network "$NETNS" \
  -e MISE_ENV=e2e \
  -v "$ENV_FILE":/app/backend/.env.e2e:ro \
  --read-only --tmpfs /tmp \
  "$BACKEND_IMAGE"

wait_for "web /health" curl -fsS http://localhost:9293/health

log "starting edge (Caddy :8080 -> localhost:9292)"
docker run -d --name tayaway-e2e-edge --network "$NETNS" \
  -e SITE_ADDRESS="http://:8080" \
  -e BACKEND_UPSTREAM="localhost:9292" \
  "$EDGE_IMAGE"

wait_for "edge /health" curl -fsS http://localhost:8080/health

log "stack up — edge http://localhost:8080, backend http://localhost:9293"
