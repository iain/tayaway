#!/bin/sh
# Guard against forgetting to bump CACHE_VERSION when the pool-cache schema
# changes. The IndexedDB pool cache is invalidated by comparing the stored
# cacheVersion against the current CACHE_VERSION constant on app startup; if
# the shape of the serialized objects changes but CACHE_VERSION doesn't,
# existing users carry forward a stale cache that the new code will read
# incorrectly.
#
# Rule: if the current branch touches either poolDb.ts or types/pool.ts,
# CACHE_VERSION in poolDb.ts must differ from its value on the base branch.
# No escape hatch — bumping the constant is free and the rule stays simple.
#
# Runs as part of `mise run check` so it fires both locally and in CI.

set -eu

BASE="${CACHE_VERSION_CHECK_BASE:-main}"
SCHEMA_FILES='^frontend/src/(api/poolDb|types/pool)\.ts$'

# Skip entirely if the base branch is missing (shallow clones, first build,
# rebase in progress). Better to be silent than to fail noisily when we
# can't compare.
if ! git rev-parse --verify --quiet "${BASE}" >/dev/null; then
  exit 0
fi

# Nothing to check if we ARE the base branch.
if [ "$(git rev-parse HEAD)" = "$(git rev-parse "${BASE}")" ]; then
  exit 0
fi

# Exit quietly if neither schema file changed.
CHANGED=$(git diff --name-only "${BASE}...HEAD" | grep -E "${SCHEMA_FILES}" || true)
if [ -z "${CHANGED}" ]; then
  exit 0
fi

extract_version() {
  grep -E '^const CACHE_VERSION = [0-9]+$' | grep -oE '[0-9]+' | head -1
}

BASE_VERSION=$(git show "${BASE}:frontend/src/api/poolDb.ts" | extract_version || true)
HEAD_VERSION=$(cat frontend/src/api/poolDb.ts | extract_version || true)

if [ -z "${BASE_VERSION}" ] || [ -z "${HEAD_VERSION}" ]; then
  echo "check:cache-version: could not extract CACHE_VERSION; check regex in this script"
  exit 1
fi

if [ "${BASE_VERSION}" = "${HEAD_VERSION}" ]; then
  cat <<EOF >&2
check:cache-version failed

  One of the pool-cache schema files changed in this branch:
$(echo "${CHANGED}" | sed 's/^/    - /')

  ...but CACHE_VERSION in frontend/src/api/poolDb.ts is still ${HEAD_VERSION}
  on both ${BASE} and HEAD.

  Bump CACHE_VERSION so users' stale IndexedDB caches get invalidated on
  their next app load. Do this even for changes that look compatible
  (rename, new optional field, re-ordering) — the cost is zero and the
  rule stays simple.

  If you're absolutely sure this change cannot touch the serialized shape
  (e.g. changed only a comment or a log line), bump the version anyway.
  One extra cache invalidation is cheaper than one user reporting a bug.
EOF
  exit 1
fi

echo "check:cache-version: CACHE_VERSION bumped ${BASE_VERSION} → ${HEAD_VERSION}"
