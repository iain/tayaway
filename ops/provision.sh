#!/usr/bin/env bash
#
# Idempotent provisioning for the OVH VPS. Cloud-init isn't available on
# VPS (the OVH terraform provider doesn't expose user_data and the
# product doesn't run cloud-init at order time), so this script is the
# *only* OS-side code path — both first-time setup and every subsequent
# tweak land here. Safe to re-execute: every step is either a no-op or
# converges.
#
# Two sentinel files gate the once-only work:
#   /etc/tayaway/bootstrap.done       → apt + user + OS configs + nftables
#                                       on port 22. Set during section 1.
#   /etc/tayaway/sshd-hardened.done   → port flipped to 50022, AllowUsers
#                                       tayaway, ssh.socket → ssh.service,
#                                       nftables rewritten. Set during
#                                       section 7. Only runs on tayaway@
#                                       so the first ubuntu@:22 run stays
#                                       reachable for the kernel-reboot
#                                       reconnect.
#
# Per-run work (sections 2–6) happens every invocation: kernel-reboot
# check, age-key check (tayaway@ only), quadlet sync, daemon-reload,
# image pre-pull. Each is a no-op when there's nothing to do.
#
# Net first-time-bring-up flow for the operator:
#   provision ubuntu@<ip>      → bootstrap, reboot if needed, exit
#   scp age key, ssh tayaway   → drop /etc/tayaway/age.key
#   provision tayaway@<ip>     → age check, quadlets, harden ssh, exit
#   update ~/.ssh/config       → Port 50022 / User tayaway
#   provision tayaway@<host>   → idempotent re-runs from here on out
#
# Usage:
#   # First run, immediately after ordering the VPS. Connect as whatever
#   # user the OVH image exposes — `ubuntu` on Ubuntu cloud images,
#   # `debian` on Debian, `root` on the generic VPS image. The script
#   # uses $SUDO_USER on the remote side to find the right
#   # authorized_keys and mirrors them to a freshly-created tayaway user.
#   mise run vm:provision ubuntu@<ip-or-hostname>
#
#   # Every run after that, including all Phase-4+ deploys. Direct root
#   # ssh is locked after first-run setup, so connect as tayaway here.
#   mise run vm:provision tayaway@new.tayaway.nl

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <ssh-target>" >&2
  echo "  first run:  $0 ubuntu@<ip>   # or root@, debian@ — whatever the image exposes" >&2
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
  fail2ban \
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

# Mirror the connecting user's authorized_keys onto tayaway so
# `ssh tayaway@host` works on the second run. The connecting user is
# whoever invoked sudo — `ubuntu` on Ubuntu cloud images, `debian` on
# Debian, `root` on the generic VPS image. SUDO_USER unwraps that
# without us having to thread the username through ssh.
SRC_USER="${SUDO_USER:-root}"
SRC_HOME="$(getent passwd "$SRC_USER" | cut -d: -f6)"
SRC_KEYS="$SRC_HOME/.ssh/authorized_keys"
if [ ! -s "$SRC_KEYS" ]; then
  echo "ERROR: $SRC_KEYS is empty or missing — drop your ssh key in $SRC_KEYS before retrying so we have something to mirror to tayaway." >&2
  exit 1
fi
install -d -m 0700 -o tayaway -g tayaway /home/tayaway/.ssh
install -m 0600 -o tayaway -g tayaway "$SRC_KEYS" /home/tayaway/.ssh/authorized_keys

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
    # ssh on 22 during bootstrap so the first-run connection (and any
    # kernel-update reboot reconnect) keeps working. The hardening
    # section at the end of the script rewrites this to dport 50022.
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
  tayaway@*)
    step "Verifying /etc/tayaway/age.key exists"
    if ! ssh_run 'sudo test -f /etc/tayaway/age.key'; then
      echo "ERROR: /etc/tayaway/age.key not found on $TARGET." >&2
      echo "  Drop it as tayaway, then re-run:" >&2
      echo "    scp ~/.config/sops/age/keys.txt $TARGET:/tmp/age.key" >&2
      echo "    ssh $TARGET 'sudo install -m 0400 -o root -g root /tmp/age.key /etc/tayaway/age.key && rm /tmp/age.key'" >&2
      exit 1
    fi
    ;;
  *)
    step "Skipping age-key check (connected as non-tayaway — first-run setup; drop the key and re-run as tayaway@)"
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

# ── 7. SSH hardening (only runs on the second-ever provision) ───────────────
# Restricted to tayaway@ invocations and gated by /etc/tayaway/sshd-hardened.done
# so it runs exactly once, on the operator's second provision after they've
# dropped the age key. Sequence matters:
#
#   1. We're connected as tayaway@ on port 22 (still allowed); existing
#      session survives the changes below because:
#        * nftables uses `ct state established,related accept` — the
#          flushed-and-reloaded ruleset keeps this connection alive.
#        * sshd reload sends SIGHUP to the master; per-connection sshd
#          children (which own our session) are unaffected.
#   2. Disabling ssh.socket + enabling ssh.service is necessary on
#      Ubuntu 22.04+ because socket activation overrides the Port
#      directive in sshd_config. With the socket gone, sshd.service
#      reads the new Port and binds 50022.
#   3. We do this LAST so no further `ssh_run` calls need to reconnect
#      on the new port. Once the script exits, the operator updates
#      `~/.ssh/config` to Port 50022 for future runs.

if [[ "$TARGET" != tayaway@* ]]; then
  echo
  echo "→ Skipping ssh hardening (connected as non-tayaway — re-run as tayaway@ to harden)"
elif ssh_run 'sudo test -f /etc/tayaway/sshd-hardened.done' 2>/dev/null; then
  echo
  echo "→ ssh already hardened (sshd-hardened.done present) — skipping"
else
  step "Hardening sshd (port 50022, AllowUsers tayaway, password auth off, root locked)"
  ssh_sudo_script <<'EOF'
set -euo pipefail

# Rewrite nftables to drop port 22 and accept 50022 instead. Reload
# preserves established connections, so this script's own ssh keeps
# working until the script exits.
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
    # ssh on 50022 — matches the legacy prod VPS so cutover-time ssh
    # config doesn't need a per-host mental switch.
    tcp dport 50022 accept
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
systemctl reload nftables

# sshd_config tweaks. Idempotent sed-with-fallback: rewrite the line if
# present in any form, otherwise append.
sshd_set() {
  local key="$1" value="$2"
  if grep -qE "^[[:space:]]*${key}[[:space:]]+" /etc/ssh/sshd_config; then
    sed -i "s/^[[:space:]]*${key}[[:space:]].*/${key} ${value}/" /etc/ssh/sshd_config
  else
    printf '%s %s\n' "$key" "$value" >> /etc/ssh/sshd_config
  fi
}
sshd_set PasswordAuthentication no
sshd_set PermitRootLogin no
sshd_set ChallengeResponseAuthentication no
sshd_set KbdInteractiveAuthentication no
sshd_set Port 50022
sshd_set AllowUsers tayaway

# Lock the root account password — combined with PermitRootLogin no
# above, root cannot authenticate at all.
passwd -l root >/dev/null

# Ubuntu 22.04+ ships ssh.socket enabled; the Port in sshd_config is
# silently ignored under socket activation. Switch to direct
# ssh.service so Port 50022 takes effect. The active ssh session is in
# sshd@<id>.service (a template instance spawned by the socket), which
# is independent of both ssh.socket and ssh.service — disabling the
# socket and starting the service doesn't kill it.
if systemctl is-active --quiet ssh.socket 2>/dev/null; then
  systemctl disable --now ssh.socket
  systemctl enable --now ssh.service
else
  # No socket activation — direct service. Reload keeps connections;
  # `ssh` is the Ubuntu unit name, `sshd` is Debian's older convention.
  systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
fi

touch /etc/tayaway/sshd-hardened.done
echo "ssh hardening complete — port 50022, AllowUsers tayaway."
EOF

  cat <<NOTICE

──────────────────────────────────────────────────────────────────────
  SSH is now on port 50022 and only the 'tayaway' user can connect.
  Update ~/.ssh/config so subsequent runs find the new port:

    Host new.tayaway.nl
      Port 50022
      User tayaway
      IdentityFile ~/.ssh/id_ed25519

  Your CURRENT ssh session is still alive (sshd reload preserved it),
  but ANY NEW ssh attempt without the Port 50022 line will fail.
──────────────────────────────────────────────────────────────────────
NOTICE
fi

echo
echo "✓ Provision complete for $TARGET"
