#!/usr/bin/env bash
#
# Idempotent provisioning for the OVH VPS. Cloud-init isn't available on
# VPS (the OVH terraform provider doesn't expose user_data and the
# product doesn't run cloud-init at order time), so this script is the
# *only* OS-side code path — both first-time setup and every subsequent
# tweak land here. Safe to re-execute: every step is either a no-op or
# converges.
#
# Order of operations (numbered sections below):
#   1. Bootstrap once: apt packages, tayaway user, OS configs, nftables.
#      Guarded by /etc/tayaway/bootstrap.done so it never runs twice.
#   2. Reboot if a kernel update landed.
#   3. Per-run: verify age key, sync quadlets, daemon-reload, pre-pull.
#
# Usage:
#   # First run, immediately after ordering the VPS — OVH only gives you
#   # root. The script creates `tayaway` and mirrors the authorized_keys.
#   mise run vm:provision root@vps123456.vps.ovh.net
#
#   # Every run after that, including all Phase-4+ deploys.
#   mise run vm:provision tayaway@new.tayaway.nl

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <ssh-target>" >&2
  echo "  first run:  $0 root@vps123456.vps.ovh.net" >&2
  echo "  later runs: $0 tayaway@new.tayaway.nl" >&2
  exit 2
fi

TARGET="$1"

# All paths relative to this script. Lets you invoke it from anywhere
# (mise task, CI, a fresh checkout) without cd'ing first.
OPS_DIR="$(cd "$(dirname "$0")" && pwd)"
QUADLET_DIR="$OPS_DIR/quadlet"

ssh_run() {
  # -T disables pseudo-tty (cleaner output, exit codes reliable).
  # StrictHostKeyChecking=accept-new accepts unknown hosts on first
  # contact but errors on a *changed* key — MITM-resistant on known
  # hosts without forcing the operator to pre-populate known_hosts.
  ssh -T -o StrictHostKeyChecking=accept-new "$TARGET" "$@"
}

# Heredoc helper: pipes a script through ssh + sudo so the remote side
# runs it under bash -s with root privileges. `sudo` is a no-op when
# TARGET is root@; needed once we switch to tayaway@.
ssh_sudo_script() {
  ssh -T -o StrictHostKeyChecking=accept-new "$TARGET" 'sudo bash -s'
}

step() {
  printf '\n→ %s\n' "$*"
}

# ── 1. First-time OS bootstrap ──────────────────────────────────────────────
# Everything cloud-init used to do, gated by a sentinel so it runs once.
# The remote script is a single heredoc so we get one ssh round-trip
# instead of N — meaningfully faster on first run, and easier to read.

step "Checking whether OS bootstrap has already run on $TARGET"
if ssh_run 'sudo test -f /etc/tayaway/bootstrap.done' 2>/dev/null; then
  echo "  bootstrap.done present — skipping first-time setup"
else
  echo "  no sentinel — running first-time setup"
  step "Installing packages and writing OS configs"
  # Quoted heredoc ('EOF') so the operator's local shell doesn't try to
  # expand $vars before they reach the remote.
  ssh_sudo_script <<'EOF'
set -euo pipefail

# Pin nothing — unattended-upgrades will track the latest in the
# distribution anyway.
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y upgrade
apt-get install -y --no-install-recommends \
  podman \
  skopeo \
  nftables \
  unattended-upgrades \
  rsync \
  curl \
  ca-certificates \
  gnupg

# Tayaway user — drives deploys and the container manager. Quadlet units
# land in /etc/containers/systemd/ (root-owned, system-wide); containers
# run under their own UIDs inside their user namespaces, so this user
# only needs ssh + sudo to push new images and reload.
if ! id tayaway >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash --groups systemd-journal tayaway
fi
install -m 0440 /dev/stdin /etc/sudoers.d/tayaway <<'SUDOERS'
tayaway ALL=(ALL) NOPASSWD:ALL
SUDOERS

# Mirror root's authorized_keys onto tayaway so `ssh tayaway@host` works
# immediately on the second run. Skip if root has none (someone ordered
# with a password, not an ssh key — error out so they fix it before we
# create a passwordless sudoer with no keys).
if [ ! -s /root/.ssh/authorized_keys ]; then
  echo "ERROR: /root/.ssh/authorized_keys is empty — re-order the VPS with an ssh key attached, or scp your key into /root/.ssh/authorized_keys first." >&2
  exit 1
fi
install -d -m 0700 -o tayaway -g tayaway /home/tayaway/.ssh
install -m 0600 -o tayaway -g tayaway /root/.ssh/authorized_keys /home/tayaway/.ssh/authorized_keys

# Tayaway state dir — age private key lands here (operator hand-drops
# it after this script's first run completes).
install -d -m 0755 -o root -g root /etc/tayaway
install -d -m 0755 -o root -g root /etc/containers/systemd

# Journald caps — without these, weeks of falcon + caddy access logs
# eat the whole boot disk on a busy day.
install -d -m 0755 /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/tayaway.conf <<'JOURNAL'
[Journal]
SystemMaxUse=2G
MaxRetentionSec=30d
JOURNAL
systemctl restart systemd-journald

# Security updates without operator intervention; reboots stay manual so
# a kernel CVE can't surprise-reboot a busy node mid-incident. The
# distro_id / distro_codename vars are expanded by unattended-upgrades
# itself at run time — they're literal in the file.
cat > /etc/apt/apt.conf.d/52unattended-upgrades-local <<'UNATTENDED'
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Allowed-Origins {
  "${distro_id}:${distro_codename}";
  "${distro_id}:${distro_codename}-security";
  "${distro_id}ESMApps:${distro_codename}-apps-security";
  "${distro_id}ESM:${distro_codename}-infra-security";
};
UNATTENDED

# Baseline nftables ruleset. Inbound restricted to ssh + http(s); forward
# stays accept so podman's own NAT/forward rules (installed by the runtime,
# not visible here) keep working. Outbound stays wide open — the stack
# legitimately reaches GHCR, OVH S3, db-ip.com, ACME, and ntfy.sh, and a
# moving target of CIDRs is more brittle than the value it adds.
cat > /etc/nftables.conf <<'NFT'
#!/usr/sbin/nft -f
flush ruleset

table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;
    ct state established,related accept
    iifname "lo" accept
    ip protocol icmp accept
    ip6 nexthdr icmpv6 accept
    tcp dport 22 accept
    tcp dport { 80, 443 } accept
  }

  chain forward {
    type filter hook forward priority 0; policy accept;
  }

  chain output {
    type filter hook output priority 0; policy accept;
  }
}
NFT
systemctl enable --now nftables

touch /etc/tayaway/bootstrap.done
echo "OS bootstrap complete."
EOF
fi

# ── 2. Reboot if needed ─────────────────────────────────────────────────────
# `apt-get upgrade` might have pulled in a new kernel. The marker file
# is the canonical Debian/Ubuntu way to detect it. Reboot once, wait for
# ssh to come back, then continue. Skipped on every run after the first.

step "Checking for pending reboot (kernel update)"
if ssh_run 'sudo test -f /var/run/reboot-required' 2>/dev/null; then
  echo "  reboot-required marker present — rebooting"
  # `nohup` + `&` so systemd-shutdown doesn't kill our ssh before the
  # exit syscall lands. `|| true` because the ssh exit code on a
  # remote-initiated reboot is racy (sometimes 0, sometimes 255).
  ssh_run 'sudo nohup shutdown -r +0 >/dev/null 2>&1 &' || true
  echo "  waiting for $TARGET to come back up"
  sleep 15
  deadline=$(($(date +%s) + 300))
  until ssh_run 'true' 2>/dev/null; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "ERROR: VPS did not come back within 5 minutes of reboot." >&2
      exit 1
    fi
    sleep 5
  done
  echo "  back up"
else
  echo "  no reboot needed"
fi

# ── 3. Verify the age key is in place ───────────────────────────────────────
# The age private key is the one secret the operator hand-drops. Bail
# loudly if it isn't there — without it, mise's sops integration can't
# decrypt backend/.env.production.yaml and the web container won't start.
# Skipped on `root@` first runs (operator hasn't dropped the key yet);
# required on `tayaway@` runs.

case "$TARGET" in
  root@*)
    step "Skipping age-key check (running as root@ — first-time setup; drop the key and re-run as tayaway@)"
    ;;
  *)
    step "Verifying /etc/tayaway/age.key exists"
    if ! ssh_run 'sudo test -f /etc/tayaway/age.key'; then
      echo "ERROR: /etc/tayaway/age.key not found on $TARGET." >&2
      echo "  Drop it as root, then re-run:" >&2
      echo "    scp ~/.config/sops/age/keys.txt $TARGET:/tmp/age.key" >&2
      echo "    ssh $TARGET 'sudo install -m 0400 -o root -g root /tmp/age.key /etc/tayaway/age.key && rm /tmp/age.key'" >&2
      exit 1
    fi
    ;;
esac

# ── 4. Push quadlet units ───────────────────────────────────────────────────
# Phase 3 lands the directory; Phase 4 fills it in. The repo is the source
# of truth: `--delete-after` will remove any unit in /etc/containers/systemd/
# that isn't in the repo. Don't hand-drop experimental units on the VPS
# and expect them to survive a provision.

step "Syncing quadlet units to /etc/containers/systemd/"
if compgen -G "$QUADLET_DIR"/* >/dev/null; then
  # rsync to /tmp first, then `sudo rsync` to the root-owned destination
  # — saves an ssh round-trip per file vs `rsync --rsync-path "sudo rsync"`.
  rsync -az --delete-after \
    -e 'ssh -o StrictHostKeyChecking=accept-new' \
    "$QUADLET_DIR/" "$TARGET:/tmp/tayaway-quadlet/"
  ssh_run "sudo rsync -a --delete-after /tmp/tayaway-quadlet/ /etc/containers/systemd/ && rm -rf /tmp/tayaway-quadlet"
else
  echo "  quadlet/ is empty — skipping (this is expected at the end of Phase 3)"
fi

# ── 5. systemd daemon-reload ────────────────────────────────────────────────
# Generated quadlet units are emitted under /run/systemd/generator/ at
# daemon-reload time. Safe to run on every provision — it's the
# documented way to re-render after editing a .container.

step "Reloading systemd"
ssh_run 'sudo systemctl daemon-reload'

# ── 6. Pre-pull current image SHAs ──────────────────────────────────────────
# Quadlet's `Image=` directive pulls on first start; doing it here instead
# surfaces auth/network/missing-tag errors during provisioning rather
# than during a deploy outage. Tags come from `images.txt` in the ops
# directory when present — Phase 4 will start writing one alongside the
# quadlet units; until then this is a no-op.

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
