#!/usr/bin/env bash
#
# Idempotent app-side provisioning for the new VM. Cloud-init handles the
# once-only OS bootstrap (`ops/cloud-init.yaml`); this script is the bit
# you re-run whenever the quadlet units or pre-pull list changes. Safe to
# re-execute — every step either is a no-op or converges.
#
# Usage:
#   mise run vm:provision <ssh-target>           # default user
#   mise run vm:provision tayaway@new.tayaway.nl # explicit
#
# Required on the local end: ssh access to the target as a sudoer.
# Required on the remote end: cloud-init has finished AND the first-boot
# reboot it schedules via power_state has completed. The first thing this
# script does is poll `cloud-init status --wait` across that reboot — see
# the "Wait for cloud-init" step below.

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <ssh-target>" >&2
  echo "  e.g. $0 tayaway@new.tayaway.nl" >&2
  exit 2
fi

TARGET="$1"

# All paths are expressed relative to this script. Lets you invoke it
# from anywhere (mise tasks, CI, a fresh checkout) without cd'ing first.
OPS_DIR="$(cd "$(dirname "$0")" && pwd)"
QUADLET_DIR="$OPS_DIR/quadlet"

ssh_run() {
  # -T disables pseudo-tty allocation (cleaner output, exit codes
  # reliable). StrictHostKeyChecking=accept-new accepts unknown hosts on
  # first contact but errors on a *changed* key — protects against MITM
  # on a known host without forcing the operator to pre-populate
  # known_hosts before running this for the first time.
  ssh -T -o StrictHostKeyChecking=accept-new "$TARGET" "$@"
}

step() {
  printf '\n→ %s\n' "$*"
}

# ── 1. Wait for cloud-init ──────────────────────────────────────────────────
# cloud-init.yaml schedules a reboot via `power_state` at the end of
# first-boot to pick up the upgraded kernel. We need to be on the *second*
# boot before pushing config, otherwise the reboot can cut a sync mid-flight.
#
# `cloud-init status --wait` blocks until cloud-init reports `done` and
# returns 0/1/2 for ok/crashed/recoverable-errors. On first boot it
# returns 0 right before the reboot fires; on second boot it returns 0
# again, this time stably. We poll twice with a sleep in between — if the
# second poll still works over the same TCP path, no reboot is in flight,
# so we are post-reboot.

step "Waiting for cloud-init to finish on $TARGET (across the first-boot reboot)"
deadline=$(($(date +%s) + 600))
while :; do
  if ssh_run 'sudo cloud-init status --wait >/dev/null' 2>/dev/null; then
    sleep 15
    if ssh_run 'sudo cloud-init status' 2>/dev/null | grep -qE '^status: (done|disabled)$'; then
      echo "  cloud-init done"
      break
    fi
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "ERROR: cloud-init did not reach a stable done state within 10 minutes." >&2
    echo "  ssh in manually and check 'sudo cloud-init status --long' + journalctl -u cloud-final." >&2
    exit 1
  fi
  echo "  not yet — reboot likely still in flight, retrying in 10s"
  sleep 10
done

# ── 2. Confirm the age key is in place ──────────────────────────────────────
# The age private key is the one secret the operator hand-drops (per the
# issue's "manual steps that can't or shouldn't be scripted" line). Bail
# loudly if it isn't present — without it, mise's sops integration can't
# decrypt backend/.env.production.yaml and the web container won't start.

step "Verifying /etc/tayaway/age.key exists"
if ! ssh_run 'sudo test -f /etc/tayaway/age.key'; then
  echo "ERROR: /etc/tayaway/age.key not found on $TARGET." >&2
  echo "  scp the age private key as root: scp age.key $TARGET:/tmp/ && ssh $TARGET 'sudo install -m 0400 -o root -g root /tmp/age.key /etc/tayaway/age.key && rm /tmp/age.key'" >&2
  exit 1
fi

# ── 3. Push quadlet units ───────────────────────────────────────────────────
# Phase 3 lands the directory; Phase 4 fills it in. Tolerate an empty
# quadlet dir so this script doesn't fail on the recipe alone — the only
# thing it should never do is silently skip files when they DO exist.
#
# The repo is the source of truth: `--delete-after` will remove any unit
# in /etc/containers/systemd/ that isn't in the repo. Don't hand-drop
# experimental units on the VM and expect them to survive a provision.

step "Syncing quadlet units to /etc/containers/systemd/"
if compgen -G "$QUADLET_DIR"/* >/dev/null; then
  # Sync via the tayaway user, then `sudo rsync` to root-owned destination.
  rsync -az --delete-after \
    -e 'ssh -o StrictHostKeyChecking=accept-new' \
    "$QUADLET_DIR/" "$TARGET:/tmp/tayaway-quadlet/"
  ssh_run "sudo rsync -a --delete-after /tmp/tayaway-quadlet/ /etc/containers/systemd/ && rm -rf /tmp/tayaway-quadlet"
else
  echo "  quadlet/ is empty — skipping (this is expected at the end of Phase 3)"
fi

# ── 4. systemd daemon-reload ────────────────────────────────────────────────
# Generated quadlet units are emitted under /run/systemd/generator/ at
# daemon-reload time. Safe to run on every provision — it's the
# documented way to re-render after editing a .container.

step "Reloading systemd"
ssh_run 'sudo systemctl daemon-reload'

# ── 5. Pre-pull current image SHAs ──────────────────────────────────────────
# Quadlet's `Image=` directive pulls on the first start; doing it here
# instead surfaces auth/network/missing-tag errors during provisioning
# rather than during a deploy outage. Tags come from
# `images.txt` in the ops directory when present — Phase 4 will start
# writing one alongside the quadlet units; until then this is a no-op.

if [ -f "$OPS_DIR/images.txt" ]; then
  step "Pre-pulling images listed in ops/images.txt"
  while IFS= read -r image; do
    [ -z "$image" ] && continue
    case "$image" in \#*) continue ;; esac
    echo "  pulling $image"
    ssh_run "sudo podman pull '$image'"
  done < "$OPS_DIR/images.txt"
else
  echo "→ ops/images.txt absent — skipping pre-pull (filled in during Phase 4)"
fi

echo
echo "✓ Provision complete for $TARGET"
