#!/usr/bin/env bash
#
# Smoke-tests the static container's Caddy config — the SPA-serving half that
# used to live inside the edge image (containers/Caddyfile).
#
# The split that makes this file necessary: the shared edge is the platform's
# and is a stock caddy image with an infra-owned config, so tayaway's routing
# and its own security headers no longer travel together. Nothing in the
# private infra repo can be exercised from this repo's CI, but the half that
# *is* tayaway's — the document headers, the cache policy, the SPA fallback,
# the precompressed siblings — is exactly what this asserts.
#
# Two modes:
#   IMAGE=<ref> containers/static-smoke.sh   test an already-built image (CI)
#   containers/static-smoke.sh               build a fixture image from
#                                            containers/Caddyfile.static plus a
#                                            synthetic dist (local, ~seconds,
#                                            no toolchain image needed)
#
# The fixture mode is the fast inner loop: the thing under test is the
# Caddyfile, not the frontend build, so a handful of stub files exercise every
# assertion below. Its .br/.gz siblings hold arbitrary bytes on purpose —
# `Accept-Encoding` requests here assert *which sibling Caddy picked*, and
# curl is never asked to decode them.
set -euo pipefail

cd "$(dirname "$0")/.."

IMAGE="${IMAGE:-}"
CID=
BUILD_CTX=

# CI and e2e/containerised-up.sh use docker; the repo's containers:up task uses
# podman. Either builds and runs this fine, so take whichever is here.
CLI="${CONTAINER_CLI:-}"
if [ -z "$CLI" ]; then
  if command -v docker >/dev/null 2>&1; then
    CLI=docker
  elif command -v podman >/dev/null 2>&1; then
    CLI=podman
  else
    echo "✗ need docker or podman on PATH" >&2
    exit 1
  fi
fi

# shellcheck disable=SC2329  # invoked by the EXIT trap below, not directly.
cleanup() {
  [ -n "$CID" ] && "$CLI" rm -f "$CID" >/dev/null 2>&1
  [ -n "$BUILD_CTX" ] && rm -rf "$BUILD_CTX"
  return 0
}
trap cleanup EXIT

fail=0
check() { # <desc> <expected> <actual>
  if [ "$2" = "$3" ]; then
    printf '  \033[32m✓\033[0m %s\n' "$1"
  else
    printf '  \033[31m✗\033[0m %s\n      expected: %s\n      actual:   %s\n' "$1" "$2" "$3"
    fail=1
  fi
}
contains() { # <desc> <needle> <haystack>
  case "$3" in
  *"$2"*) printf '  \033[32m✓\033[0m %s\n' "$1" ;;
  *)
    printf '  \033[31m✗\033[0m %s\n      wanted substring: %s\n      in: %s\n' "$1" "$2" "$3"
    fail=1
    ;;
  esac
}
absent() { # <desc> <actual>
  if [ -z "$2" ]; then
    printf '  \033[32m✓\033[0m %s\n' "$1"
  else
    printf '  \033[31m✗\033[0m %s\n      expected no header, got: %s\n' "$1" "$2"
    fail=1
  fi
}

# Header lookup off a `curl -D` dump. Case-insensitive (HTTP/2 lowercases
# field names, HTTP/1.1 does not) and CR-stripped.
hdr() { # <dump-file> <field>
  awk -v want="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')" '
    { line = $0; sub(/\r$/, "", line)
      split(line, kv, ": ")
      k = tolower(kv[1])
      if (k == want) { sub(/^[^:]*: /, "", line); print line } }
  ' "$1"
}

# ── Build the fixture image when no IMAGE was handed in ──────────────────────
if [ -z "$IMAGE" ]; then
  echo "▸ building fixture image from containers/Caddyfile.static"
  BUILD_CTX=$(mktemp -d)
  mkdir -p "$BUILD_CTX/dist/assets"
  cp containers/Caddyfile.static "$BUILD_CTX/Caddyfile.static"

  printf '<!doctype html><title>tayaway fixture</title><div id="app"></div>\n' \
    >"$BUILD_CTX/dist/index.html"
  printf 'console.log("fixture")\n' \
    >"$BUILD_CTX/dist/assets/app.deadbeef.js"
  # Not real brotli/gzip — see the header comment.
  printf 'FIXTURE-BROTLI\n' >"$BUILD_CTX/dist/assets/app.deadbeef.js.br"
  printf 'FIXTURE-GZIP\n' >"$BUILD_CTX/dist/assets/app.deadbeef.js.gz"

  cat >"$BUILD_CTX/Containerfile" <<'FIXTURE'
FROM caddy:2-alpine
COPY Caddyfile.static /etc/caddy/Caddyfile
COPY dist /srv/dist
FIXTURE

  IMAGE=tayaway-static-fixture:smoke
  "$CLI" build -q -t "$IMAGE" -f "$BUILD_CTX/Containerfile" "$BUILD_CTX" >/dev/null
fi

# ── Run it and find the port ─────────────────────────────────────────────────
echo "▸ starting $IMAGE"
CID=$("$CLI" run -d -p 127.0.0.1:0:8080 "$IMAGE")
PORT=$("$CLI" port "$CID" 8080 | head -1 | sed 's/.*://')
BASE="http://127.0.0.1:$PORT"

for _ in $(seq 1 40); do
  if curl -fsS -o /dev/null "$BASE/" 2>/dev/null; then break; fi
  sleep 0.25
done
if ! curl -fsS -o /dev/null "$BASE/"; then
  echo "✗ container never served / — logs:" >&2
  "$CLI" logs "$CID" >&2 || true
  exit 1
fi

# A real dist has content-hashed names; the fixture has one known asset. Pick a
# .js under /assets that has a .br sibling, so the precompressed assertions
# exercise the same path in both modes.
# shellcheck disable=SC2016  # $f is expanded by the container's shell, not this one.
ASSET=$("$CLI" exec "$CID" sh -c \
  'cd /srv/dist/assets 2>/dev/null && for f in *.js; do [ -f "$f.br" ] && echo "$f" && break; done' || true)
if [ -z "$ASSET" ]; then
  echo "✗ no /assets/*.js with a .br sibling found in the image" >&2
  "$CLI" exec "$CID" sh -c 'ls -la /srv/dist /srv/dist/assets' >&2 || true
  exit 1
fi
echo "  using asset: $ASSET"

D=$(mktemp -d)
trap 'cleanup; rm -rf "$D"' EXIT

# ── The SPA shell ────────────────────────────────────────────────────────────
echo "▸ document headers and caching (GET /)"
code=$(curl -sS -D "$D/root" -o "$D/root.body" -w '%{http_code}' "$BASE/")
check "/ returns 200" "200" "$code"
contains "/ is html" "text/html" "$(hdr "$D/root" content-type)"
check "SPA shell is no-cache" "no-cache" "$(hdr "$D/root" cache-control)"

echo "▸ application policy headers (tayaway's, per D9)"
contains "CSP is enforced and same-origin by default" "default-src 'self'" "$(hdr "$D/root" content-security-policy)"
contains "CSP keeps script-src locked to self" "script-src 'self'" "$(hdr "$D/root" content-security-policy)"
contains "CSP reports to the app's endpoint" "report-uri /api/csp-report" "$(hdr "$D/root" content-security-policy)"
contains "candidate CSP is still reported" "require-trusted-types-for 'script'" "$(hdr "$D/root" content-security-policy-report-only)"
contains "Reporting-Endpoints names both groups" "csp-candidate=" "$(hdr "$D/root" reporting-endpoints)"
check "COOP severs window.opener" "same-origin" "$(hdr "$D/root" cross-origin-opener-policy)"
check "nosniff" "nosniff" "$(hdr "$D/root" x-content-type-options)"
check "framing denied" "DENY" "$(hdr "$D/root" x-frame-options)"
check "referrer policy" "strict-origin-when-cross-origin" "$(hdr "$D/root" referrer-policy)"
contains "permissions policy pins geolocation to self" "geolocation=(self)" "$(hdr "$D/root" permissions-policy)"

echo "▸ transport headers stay the platform's"
# HSTS belongs to whatever terminates TLS. This container never does, and a
# stray HSTS here would be the tell that the concern split had been undone.
absent "no HSTS from the app container" "$(hdr "$D/root" strict-transport-security)"

# ── SPA fallback ─────────────────────────────────────────────────────────────
echo "▸ client-side routing (try_files)"
code=$(curl -sS -D "$D/deep" -o "$D/deep.body" -w '%{http_code}' "$BASE/events/0198c2f1-dead-beef")
check "unknown route returns 200" "200" "$code"
check "unknown route serves the shell" "$(cat "$D/root.body")" "$(cat "$D/deep.body")"
check "rewritten shell is still no-cache" "no-cache" "$(hdr "$D/deep" cache-control)"
contains "rewritten shell still carries the CSP" "default-src 'self'" "$(hdr "$D/deep" content-security-policy)"

# ── Hashed assets ────────────────────────────────────────────────────────────
echo "▸ content-hashed assets"
code=$(curl -sS -D "$D/asset" -o /dev/null -w '%{http_code}' "$BASE/assets/$ASSET")
check "asset returns 200" "200" "$code"
check "asset is immutable" "public, immutable, max-age=31536000" "$(hdr "$D/asset" cache-control)"

echo "▸ precompressed siblings"
curl -sS -D "$D/br" -o /dev/null -H 'Accept-Encoding: br' "$BASE/assets/$ASSET"
check "brotli sibling is served" "br" "$(hdr "$D/br" content-encoding)"
check "brotli response is still immutable" "public, immutable, max-age=31536000" "$(hdr "$D/br" cache-control)"
curl -sS -D "$D/gz" -o /dev/null -H 'Accept-Encoding: gzip' "$BASE/assets/$ASSET"
check "gzip sibling is served when brotli is not accepted" "gzip" "$(hdr "$D/gz" content-encoding)"
contains "encoding is varied on" "Accept-Encoding" "$(hdr "$D/br" vary)"

echo
if [ "$fail" -eq 0 ]; then
  echo "✓ static container smoke test passed"
else
  echo "✗ static container smoke test FAILED" >&2
  "$CLI" logs "$CID" 2>&1 | tail -30 >&2 || true
fi
exit "$fail"
