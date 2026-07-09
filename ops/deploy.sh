#!/usr/bin/env bash
#
# Deploy a git SHA to a running tayaway stack: pull the app images, point the
# quadlets at the new SHA, restart in dependency order, and smoke-test
# /health — rolling back to the previously-deployed SHA if it doesn't go
# green. Replaces the manual "edit Image= in five places + vm:provision +
# restart" dance from images.txt.
#
# Source of truth is the repo working tree: this script rewrites the
# tayaway-{backend,edge,geoip} tags in ops/quadlet/*.container + ops/images.txt
# and rsyncs them to the box (the same files vm:provision syncs), so repo and
# box stay consistent whether or not you commit the bump afterwards. Commit it
# for history; nothing depends on the commit. `db` has its own image lifecycle
# and is never touched here.
#
# Usage:
#   mise run deploy tayaway@tayaway.nl            # deploy HEAD
#   mise run deploy tayaway@tayaway.nl <git-sha>  # deploy a specific SHA
#
# Env overrides:
#   DEPLOY_HEALTH_URL   health endpoint to poll (default https://<host>/health,
#                       host taken from the ssh target). Set this post-cutover
#                       if the ssh target and the public hostname diverge.
#
# CI-ready: no interactive input, no local state beyond the repo + ssh key.
# A future .github/workflows/deploy.yml can call this directly with
# `ops/deploy.sh tayaway@<host> "$GITHUB_SHA"` once a deploy SSH key + the
# DEPLOY_HEALTH_URL are wired in.

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <ssh-target> [git-sha]" >&2
  echo "  e.g. $0 tayaway@tayaway.nl" >&2
  exit 2
fi

TARGET="$1"
SHA="${2:-$(git rev-parse HEAD)}"
HOST="${TARGET##*@}"
HEALTH_URL="${DEPLOY_HEALTH_URL:-https://$HOST/health}"

# Git SHAs are 7–40 lowercase hex. Validate up front so a typo fails here
# rather than after we've started restarting containers.
if ! printf '%s' "$SHA" | grep -Eq '^[0-9a-f]{7,40}$'; then
  echo "ERROR: '$SHA' is not a valid git SHA." >&2
  exit 2
fi

# jq parses the /health version in the post-deploy check. `mise run deploy`
# provides it (see [tasks.deploy].tools in .mise.toml); direct invocations rely
# on an ambient jq (CI runners and Homebrew ship it). Fail fast rather than
# silently mis-verifying later.
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq not found. Run via 'mise run deploy', or install jq." >&2
  exit 2
fi

OPS_DIR="$(cd "$(dirname "$0")" && pwd)"
QUADLET_DIR="$OPS_DIR/quadlet"
# Files that pin the app SHA. db.container is intentionally excluded.
SHA_FILES=(
  "$QUADLET_DIR/web.container"
  "$QUADLET_DIR/migrate.container"
  "$QUADLET_DIR/edge.container"
  "$QUADLET_DIR/geoip.container"
  "$OPS_DIR/images.txt"
)

ssh_run() {
  ssh -T -o StrictHostKeyChecking=accept-new "$TARGET" "$@"
}

step() { printf '\n→ %s\n' "$*"; }

# ── rollback bookkeeping ──────────────────────────────────────────────────────
# sed -i.bak leaves the pre-edit content beside each file; restore_files puts
# them back. Tracked so we only restore what we actually rewrote.
rewrote=0
restore_files() {
  for f in "${SHA_FILES[@]}"; do
    [ -f "$f.bak" ] && mv -f "$f.bak" "$f"
  done
}
clear_baks() {
  for f in "${SHA_FILES[@]}"; do rm -f "$f.bak"; done
}

sync_quadlets() {
  rsync -az --delete-after -e 'ssh -o StrictHostKeyChecking=accept-new' \
    "$QUADLET_DIR/" "$TARGET:/tmp/tayaway-quadlet/"
  ssh_run "sudo rsync -a --delete-after /tmp/tayaway-quadlet/ /etc/containers/systemd/ && rm -rf /tmp/tayaway-quadlet"
  ssh_run 'sudo systemctl daemon-reload'
}

# Restart the whole stack in ONE transaction so systemd coalesces it into a
# single restart job per unit, in dependency order (migrate oneshot re-runs
# config:validate + db:migrate against the new image; web's Notify=true blocks
# until Falcon accepts connections; edge last). A non-zero here (failed
# migration, web never ready) propagates out and triggers rollback.
#
# Must be a single `systemctl restart` invocation, not three: web has
# Requires=migrate.service, so a standalone `restart migrate` already bounces
# web. Issuing a separate `restart web` right after then lands while that
# bounced web is still mid-boot and kills it (exit 1 → OnFailure page) before
# Restart=on-failure brings it back ~100ms later — a ~50/50 spurious failure.
# One transaction merges both into a single web restart, so there's no overlap.
restart_stack() {
  ssh_run 'sudo systemctl restart migrate.service web.service edge.service'
}

# Poll /health from here (exercises the real DNS → Caddy → web → db path, not
# just the container). Returns 0 on the first 200.
smoke_test() {
  local deadline=$(($(date +%s) + 45)) code
  while [ "$(date +%s)" -lt "$deadline" ]; do
    code=$(curl -fsS -o /dev/null -w '%{http_code}' -m 10 "$HEALTH_URL" 2>/dev/null || true)
    if [ "$code" = "200" ]; then
      echo "  /health → 200"
      return 0
    fi
    echo "  /health → ${code:-no response}; retrying"
    sleep 3
  done
  return 1
}

# A 200 only proves *something* healthy answered — not that the restart
# actually swapped to the new image (a container that failed to recreate would
# keep serving the old code on a 200). /health reports APP_CONFIG.git_sha, so
# confirm it's the SHA we just deployed. Compare on the 7-char short form to
# tolerate full-vs-short. An empty version means a pre-version-feature image is
# answering: warn but don't fail, so rolling back to an old SHA still works.
verify_version() {
  local served
  served=$(curl -fsS -m 10 "$HEALTH_URL" 2>/dev/null | jq -r '.version // ""')
  if [ -z "$served" ]; then
    echo "  version → none reported (pre-version image?) — skipping version check"
    return 0
  elif [ "${served:0:7}" = "${SHA:0:7}" ]; then
    echo "  version → $served (matches deployed SHA)"
    return 0
  else
    echo "  version → $served, expected ${SHA:0:7}* — restart did not swap the container" >&2
    return 1
  fi
}

rollback() {
  step "Rolling back to the previously-deployed SHA"
  restore_files
  rewrote=0
  sync_quadlets
  # Best-effort restart on the old images; they were healthy before, so this
  # restores service even if the new SHA wedged a container.
  restart_stack || true
  if smoke_test; then
    echo "  rolled back — stack healthy on the previous SHA"
  else
    echo "  ⚠ rollback restart did not pass /health either — investigate on the box" >&2
  fi
}

# ── 1. Pre-flight: pull the target images (fail before touching the stack) ────
# Refresh the persistent GHCR authfile (/var/lib/tayaway/ghcr-auth.json, which
# self-deploy also reads); best-effort, mirroring provision.sh — the box is
# usually already logged in.
step "Logging the box in to GHCR (if a pull token is configured)"
ghcr_user=$(mise x sops -- sops decrypt --extract '["GHCR_USER"]' "$OPS_DIR/secrets.yaml" 2>/dev/null || true)
ghcr_token=$(mise x sops -- sops decrypt --extract '["GHCR_PULL_TOKEN"]' "$OPS_DIR/secrets.yaml" 2>/dev/null || true)
if [ -n "$ghcr_user" ] && [ -n "$ghcr_token" ]; then
  printf '%s' "$ghcr_token" | ssh_run "sudo podman login ghcr.io -u '$ghcr_user' --password-stdin --authfile /var/lib/tayaway/ghcr-auth.json" >/dev/null
  echo "  logged in as $ghcr_user"
else
  echo "  no GHCR creds in ops/secrets.yaml — assuming the box is already logged in"
fi

step "Pulling app images for $SHA"
pull_ok=1
for repo in tayaway-backend tayaway-edge tayaway-geoip; do
  image="ghcr.io/iain/$repo:$SHA"
  echo "  $image"
  ssh_run "sudo podman pull --authfile /var/lib/tayaway/ghcr-auth.json '$image'" >/dev/null || pull_ok=0
done
if [ "$pull_ok" != "1" ]; then
  echo "ERROR: one or more images for $SHA could not be pulled." >&2
  echo "  Has the App-images workflow finished building this SHA? Nothing was changed." >&2
  exit 1
fi

# ── 2. Point the quadlets at the new SHA ──────────────────────────────────────
step "Rewriting app image tags → $SHA"
sed -E -i.bak \
  "s#(ghcr\.io/iain/tayaway-(backend|edge|geoip):)[0-9a-f]{7,40}#\1$SHA#g" \
  "${SHA_FILES[@]}"
rewrote=1
# Surface what changed (and confirm db was left alone).
grep -rhoE 'ghcr\.io/iain/tayaway-[a-z]+:[0-9a-f]{7,40}' "${SHA_FILES[@]}" | sort -u | sed 's/^/  /'

# From here on, a failure must roll back.
trap 'echo; echo "✗ Deploy failed — rolling back."; [ "$rewrote" = 1 ] && rollback; clear_baks; exit 1' ERR

# ── 3. Apply + restart ────────────────────────────────────────────────────────
step "Syncing quadlets and restarting the stack"
sync_quadlets
restart_stack

# ── 4. Smoke-test, roll back if unhealthy ─────────────────────────────────────
step "Smoke-testing $HEALTH_URL"
if smoke_test && verify_version; then
  trap - ERR
  clear_baks
  echo
  echo "✓ Deployed $SHA to $TARGET"
  echo "  Commit the SHA bump in ops/ to record this deploy (optional — the"
  echo "  working tree and the box already agree)."
else
  trap - ERR
  echo "✗ Deploy did not verify (health or version) — rolling back." >&2
  rollback
  clear_baks
  exit 1
fi
