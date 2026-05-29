#!/usr/bin/env bash
#
# Pull-based continuous deployment. A systemd timer runs this every few
# minutes; it notices when GHCR's `:main` tag points at a newer commit than
# the box is running and deploys it — the box pulls, GitHub never pushes, so
# CI has no access to this machine. Mirrors ops/deploy.sh's proven sequence
# (pull → rewrite quadlet pins → restart migrate→web→edge → smoke-test →
# roll back on failure) but runs locally as root with no ssh.
#
# Trust model: deploys whatever `:main` resolves to. images.yml publishes only
# per-commit :<sha>; `:main` is moved solely by promote-main.yml, and only
# after CI passes on main — so a PR or a test-failing commit can't move it.
# Hardening to verify build provenance before deploy is a planned follow-up.
#
# Idempotent and safe to run on every tick: a no-op when already current, and
# a failed deploy records the bad SHA so the timer can't thrash on it — it
# stays put until a *different* SHA appears (i.e. a fix-forward commit).
set -euo pipefail

REGISTRY=ghcr.io/iain
TARGET_TAG=main
QUADLET_DIR=/etc/containers/systemd
STATE_DIR=/var/lib/tayaway
LAST_BAD="$STATE_DIR/self-deploy-last-bad"

# Image-pinned quadlets this rewrites. db is excluded — it has its own SHA
# lifecycle, exactly as in ops/deploy.sh.
FILES=(
  "$QUADLET_DIR/web.container"
  "$QUADLET_DIR/migrate.container"
  "$QUADLET_DIR/edge.container"
  "$QUADLET_DIR/geoip.container"
)

log() { printf '[self-deploy] %s\n' "$*"; }

# SHAs are 40 lowercase hex. Validate everything resolved from the registry or
# parsed off disk before it reaches podman/sed/systemctl — a tampered tag,
# label, or quadlet must not inject anything.
valid_sha() { printf '%s' "$1" | grep -Eq '^[0-9a-f]{40}$'; }

restore_baks() { for f in "${FILES[@]}"; do [ -f "$f.bak" ] && mv -f "$f.bak" "$f"; done; }
clear_baks()   { for f in "${FILES[@]}"; do rm -f "$f.bak"; done; }

# One `systemctl restart` invocation, not three: web has Requires=migrate, so a
# standalone `restart migrate` already bounces web — a separate `restart web`
# then lands mid-boot and kills it (exit 1 → OnFailure page) before it recovers.
# One transaction coalesces it into a single web restart. See ops/deploy.sh.
restart_stack() {
  systemctl restart migrate.service web.service edge.service
}

# Hit /health through the edge exactly as an external client would, but pinned
# to loopback so it doesn't depend on public DNS (works mid-cutover too). The
# site host comes from edge's SITE_ADDRESS, so this follows the apex flip
# without a code change. -k: the smoke test cares that the app answers 200,
# not about cert chain edge cases during a renewal.
smoke_test() {
  local site deadline code
  site=$(grep -oP 'SITE_ADDRESS=https?://\K[^/ ]+' "$QUADLET_DIR/edge.container")
  deadline=$(( $(date +%s) + 45 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    code=$(curl -fsS -k -o /dev/null -w '%{http_code}' -m 10 \
      --resolve "$site:443:127.0.0.1" "https://$site/health" 2>/dev/null || true)
    if [ "$code" = "200" ]; then return 0; fi
    sleep 3
  done
  return 1
}

# Belt-and-braces over the 200: confirm the running web container is actually
# the target image, so a restart that silently kept the old container can't
# pass as a successful deploy.
running_is() {
  local want="$1" img
  img=$(podman inspect web --format '{{.ImageName}}' 2>/dev/null || true)
  [ "$img" = "$REGISTRY/tayaway-backend:$want" ]
}

mkdir -p "$STATE_DIR"

# ── Resolve what main wants ───────────────────────────────────────────────────
# skopeo --format avoids parsing JSON (no jq on this box); the revision label
# is stamped by images.yml. Uses the box's persistent GHCR login.
target=$(skopeo inspect --format '{{ index .Labels "org.opencontainers.image.revision" }}' \
  "docker://$REGISTRY/tayaway-backend:$TARGET_TAG" 2>/dev/null || true)
if ! valid_sha "$target"; then
  log "could not resolve a valid SHA from :$TARGET_TAG (got '${target:-}') — GHCR auth/network? aborting"
  exit 1
fi

deployed=$(grep -oP 'tayaway-backend:\K[0-9a-f]{40}' "$QUADLET_DIR/web.container" || true)

if [ "$target" = "$deployed" ]; then
  log "up to date ($target)"
  exit 0
fi
if [ -f "$LAST_BAD" ] && [ "$target" = "$(cat "$LAST_BAD")" ]; then
  log "target $target previously failed to deploy — skipping until a new build appears"
  exit 0
fi

log "deploying $target (was ${deployed:-unknown})"

# ── Pre-flight: pull all three before touching the stack ──────────────────────
for repo in tayaway-backend tayaway-edge tayaway-geoip; do
  if ! podman pull "$REGISTRY/$repo:$target" >/dev/null; then
    log "pull failed for $repo:$target — nothing changed, aborting"
    exit 1
  fi
done

# ── Apply: rewrite pins, restart, verify; roll back on any failure ────────────
sed -E -i.bak \
  "s#(${REGISTRY}/tayaway-(backend|edge|geoip):)[0-9a-f]{7,40}#\1${target}#g" \
  "${FILES[@]}"
systemctl daemon-reload

if restart_stack && smoke_test && running_is "$target"; then
  clear_baks
  rm -f "$LAST_BAD"
  log "deployed $target — /health 200, web running target image"
  exit 0
fi

log "deploy of $target failed verification — rolling back to ${deployed:-previous}"
restore_baks
systemctl daemon-reload
restart_stack || true
if smoke_test; then
  log "rolled back — stack healthy on the previous image"
else
  log "ROLLBACK ALSO UNHEALTHY — investigate on the box" >&2
fi
# Remember the bad SHA so the next tick doesn't redeploy + re-fail it; a
# fix-forward commit changes :main to a new SHA and clears this naturally.
printf '%s\n' "$target" > "$LAST_BAD"
exit 1
