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
#   /etc/tayaway/sshd-hardened.done   → /etc/ssh/sshd_config.d/00-tayaway-
#                                       hardening.conf written (Port 50022,
#                                       AllowUsers tayaway ubuntu, password
#                                       auth off, kbd-interactive off),
#                                       nftables rewritten to 50022,
#                                       ssh.service restarted, root account
#                                       locked. Set during section 7 ONLY
#                                       after verifying sshd actually bound
#                                       50022, so a future operator can't
#                                       be locked out of a half-hardened
#                                       VPS. Runs only on tayaway@.
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
REPO_ROOT="$(cd "$OPS_DIR/.." && pwd)"
QUADLET_DIR="$OPS_DIR/quadlet"
HOST_DIR="$OPS_DIR/host"

# sops on the host decrypts only POSTGRES_PASSWORD for the stock postgres
# container (web/migrate decrypt in-container via mise). Pinned + checksum
# -verified; bump both together. linux amd64 — the VPS arch.
SOPS_VERSION=3.13.1
SOPS_SHA256=620a9d7e3352ababeca6908cea24a6e8b14ce89a448ddbd3f94f1ef3398f470a

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
    # Containers reach aardvark-dns on the podman bridge gateway (:53) for
    # container-name resolution. Without this, the default-drop input
    # silently eats those queries and every in-container lookup (db, web)
    # times out. The podman* bridges carry only our own containers.
    iifname "podman*" accept
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

# ── 3a. Ensure container-runtime packages ────────────────────────────────────
# The first-boot apt install uses --no-install-recommends, which skips
# aardvark-dns (only a *Recommends* of podman). Without it, containers get
# IPs but can't resolve each other by name — db:5432 never resolves and
# migrate spins forever. netavark is the network backend; uidmap lets the
# tayaway user run rootless podman for debugging. Idempotent and self-
# healing: installs only what's missing, so it fixes already-bootstrapped
# boxes on re-provision (the one-shot bootstrap above won't re-run).

step "Ensuring container-runtime packages (aardvark-dns, netavark, uidmap)"
ssh_sudo_script <<'EOF'
set -euo pipefail
missing=()
for pkg in aardvark-dns netavark uidmap; do
  dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
done
if [ ${#missing[@]} -gt 0 ]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends "${missing[@]}"
  echo "  installed: ${missing[*]} — restart running containers to pick up DNS"
else
  echo "  all present"
fi
EOF

# ── 3a′. podman network config (netavark + working DNS) ──────────────────────
# Two drop-ins, both load-bearing on Ubuntu:
#   - network_backend=netavark. podman picks its backend once and caches it;
#     if netavark was missing at first run it falls back to CNI (whose name
#     resolution needs a separate dnsname plugin and yields DNSEnabled=false).
#     Pinning it here keeps a rebuild off CNI regardless of install ordering.
#   - dns_servers. The host resolv.conf is systemd-resolved's 127.0.0.53
#     stub, which is unreachable from a container netns — so containers (and
#     aardvark-dns's upstream forwarding) can't resolve external hosts like
#     download.db-ip.com or the ACME endpoints. Point them at real resolvers.
# Drop-ins, so we never clobber a hand-edited containers.conf.

step "Writing podman network config (netavark + dns_servers)"
ssh_sudo_script <<'EOF'
set -euo pipefail
install -d -m 0755 /etc/containers/containers.conf.d
cat > /etc/containers/containers.conf.d/01-tayaway-netavark.conf <<'CONF'
[network]
network_backend = "netavark"
CONF
cat > /etc/containers/containers.conf.d/02-tayaway-dns.conf <<'CONF'
[containers]
dns_servers = ["1.1.1.1", "8.8.8.8"]
CONF
EOF

# ── 3b. Deliver production env files ─────────────────────────────────────────
# The encrypted yaml + plaintext dotenv are bind-mounted into web/migrate
# (mise decrypts the yaml in-process) and read by the host db-secret
# oneshot. Committed in the repo; the VPS gets a copy at /etc/tayaway/env.
# .containerignore keeps them out of the images, which is what makes
# secret rotation "edit + restart" instead of "rebuild".

step "Delivering production env files to /etc/tayaway/env/"
rsync -az -e 'ssh -o StrictHostKeyChecking=accept-new' \
  "$REPO_ROOT/backend/.env.production" \
  "$REPO_ROOT/backend/.env.production.yaml" \
  "$TARGET:/tmp/tayaway-env/"
ssh_sudo_script <<'EOF'
set -euo pipefail
install -d -m 0750 -o root -g root /etc/tayaway/env
# Plaintext config 0444; encrypted yaml 0440. Both owned by root —
# containers run as root and read them through read-only bind mounts.
install -m 0444 -o root -g root /tmp/tayaway-env/.env.production /etc/tayaway/env/.env.production
install -m 0440 -o root -g root /tmp/tayaway-env/.env.production.yaml /etc/tayaway/env/.env.production.yaml
rm -rf /tmp/tayaway-env
EOF

# ── 3c. Install sops (host-side DB-password decryption) ──────────────────────
# Pinned + checksum-verified; re-installs only when the version differs.

step "Ensuring sops $SOPS_VERSION is installed"
ssh_sudo_script <<EOF
set -euo pipefail
if [ "\$(/usr/local/bin/sops --version 2>/dev/null | awk '{print \$2}')" = "$SOPS_VERSION" ]; then
  echo "  sops $SOPS_VERSION already present"
else
  tmp=\$(mktemp)
  curl -fsSL -o "\$tmp" "https://github.com/getsops/sops/releases/download/v$SOPS_VERSION/sops-v$SOPS_VERSION.linux.amd64"
  echo "$SOPS_SHA256  \$tmp" | sha256sum -c -
  install -m 0755 "\$tmp" /usr/local/bin/sops
  rm -f "\$tmp"
  echo "  installed sops $SOPS_VERSION"
fi
EOF

# ── 3d. Install host units (DB-secret oneshot + tmpfiles) ────────────────────
# The decrypt script, its systemd unit, and the /run/tayaway tmpfiles rule.
# db.container depends on tayaway-db-secret.service; enabling it here wires
# the boot ordering. It only actually runs once the age key + env yaml are
# present (ConditionPathExists in the unit), so this is safe on first runs.

step "Installing host units (tayaway-db-secret, geoip.timer)"
rsync -az -e 'ssh -o StrictHostKeyChecking=accept-new' \
  "$HOST_DIR/" "$TARGET:/tmp/tayaway-host/"
ssh_sudo_script <<'EOF'
set -euo pipefail
install -m 0755 -o root -g root /tmp/tayaway-host/tayaway-db-secret.sh /usr/local/bin/tayaway-db-secret
install -m 0644 -o root -g root /tmp/tayaway-host/tayaway-db-secret.service /etc/systemd/system/tayaway-db-secret.service
install -m 0644 -o root -g root /tmp/tayaway-host/geoip.timer /etc/systemd/system/geoip.timer
install -m 0644 -o root -g root /tmp/tayaway-host/tayaway.tmpfiles /etc/tmpfiles.d/tayaway.conf
systemd-tmpfiles --create /etc/tmpfiles.d/tayaway.conf
systemctl daemon-reload
systemctl enable tayaway-db-secret.service
# The timer enables now; its target geoip.service is generated from the
# quadlet at the daemon-reload in the next step, so enabling the timer
# here (before that reload) is fine — it only needs geoip.service to
# exist when it fires, not when it's enabled.
systemctl enable geoip.timer
rm -rf /tmp/tayaway-host
EOF

# ── 3e. GHCR login for private image pulls ───────────────────────────────────
# backend/edge are private packages. Decrypt a read:packages token from
# ops/secrets.yaml *locally* (operator key) and pipe it to the VPS's
# `podman login` over ssh stdin — so the token only ever lands in the box's
# auth.json, never in a container env or a VM-readable file. Re-run on every
# provision (and thus every deploy), which is when pulls actually happen;
# the auth lives in tmpfs and is lost on reboot, but reboots don't pull
# (images persist on disk). Skipped cleanly if the keys aren't set yet.

step "Logging the VPS in to GHCR (if a pull token is configured)"
ghcr_user=$(mise x sops -- sops decrypt --extract '["GHCR_USER"]' "$OPS_DIR/secrets.yaml" 2>/dev/null || true)
ghcr_token=$(mise x sops -- sops decrypt --extract '["GHCR_PULL_TOKEN"]' "$OPS_DIR/secrets.yaml" 2>/dev/null || true)
if [ -n "$ghcr_user" ] && [ -n "$ghcr_token" ]; then
  printf '%s' "$ghcr_token" | ssh_run "sudo podman login ghcr.io -u '$ghcr_user' --password-stdin"
  echo "  logged in to ghcr.io as $ghcr_user"
else
  echo "  no GHCR_USER/GHCR_PULL_TOKEN in ops/secrets.yaml — skipping"
  echo "  (private-image pulls will need a one-time 'sudo podman login ghcr.io' on the VPS)"
fi

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
  pull_failed=0
  while IFS= read -r image; do
    [ -z "$image" ] && continue
    case "$image" in \#*) continue ;; esac
    echo "  pulling $image"
    # Non-fatal: backend/edge are private GHCR packages, so a fresh box
    # needs `sudo podman login ghcr.io` first. Pull=missing in the
    # quadlets retries at service start anyway, so a failed pre-pull
    # shouldn't abort the whole (otherwise idempotent) provision.
    ssh_run "sudo podman pull '$image'" || pull_failed=1
  done < "$OPS_DIR/images.txt"
  if [ "$pull_failed" = "1" ]; then
    echo "  ⚠ one or more pulls failed — if these are the private GHCR images," >&2
    echo "    log the VPS in once (read:packages PAT) and re-run:" >&2
    echo "    ssh $TARGET 'sudo podman login ghcr.io -u <github-user>'" >&2
  fi
else
  echo "→ ops/images.txt absent — skipping pre-pull"
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
  step "Hardening sshd (port 50022, AllowUsers tayaway ubuntu, password auth off, root locked)"
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
    # Containers reach aardvark-dns on the podman bridge gateway (:53) for
    # container-name resolution. Without this, the default-drop input
    # silently eats those queries and every in-container lookup (db, web)
    # times out. The podman* bridges carry only our own containers.
    iifname "podman*" accept
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

# Write all sshd hardening to a single dropin that loads BEFORE
# cloud-init's /etc/ssh/sshd_config.d/50-cloud-init.conf. The Include
# directive in the main sshd_config reads dropins in lexical order
# (per sshd_config(5): "expanded and processed in lexical order"), and
# sshd's rule for most directives (PasswordAuthentication,
# PermitRootLogin, Port, KbdInteractiveAuthentication) is "first
# occurrence wins" (per sshd_config(5): "Unless noted otherwise, for
# each keyword, the first obtained value will be used"). OVH's image
# ships 50-cloud-init.conf with `PasswordAuthentication yes`; if we
# appended to the main file instead, our `no` would lose to
# cloud-init's `yes`. 00- sorts before 50-, so this file wins.
#
# AllowUsers is a list directive (multiple entries accumulate), but
# keeping it in the same dropin keeps the whole hardening posture in
# one greppable place.
#
# Ubuntu 24.04 ships /etc/ssh/sshd_config.d/, but mkdir -p makes the
# script robust to custom images that don't.
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/00-tayaway-hardening.conf <<'SSHDCONF'
Port 50022
PasswordAuthentication no
PermitRootLogin no
KbdInteractiveAuthentication no
# tayaway is the deploy user; ubuntu is kept as a fallback so the
# operator has a way back in if tayaway's key ever goes sideways.
# ubuntu's authorized_keys is untouched by this script — only the
# mirror-to-tayaway step reads it once — so the operator's key still
# works for the fallback login.
AllowUsers tayaway ubuntu
SSHDCONF

# Validate the config before restarting — `sshd -t` is exactly what
# ssh.service's ExecStartPre runs, so a syntax error here is the
# same syntax error that would prevent restart. Bail loudly with the
# old sshd still running rather than restarting into a broken state.
sshd -t

# Lock the root account password — combined with PermitRootLogin no
# above, root cannot authenticate at all.
passwd -l root >/dev/null

# Apply by full restart, not reload. SIGHUP-based reload was observed
# to not pick up the new port cleanly on OVH's Ubuntu 24.04 image
# (sshd re-execed but kept binding the old port — the running sshd's
# `Server listening on port 22` log line contradicted what `sshd -T`
# said the effective config was). Full restart works. KillMode=process
# in ssh.service means only the master sshd is killed; per-connection
# child sshds (including our own ssh session) survive untouched.
#
# Socket-activation case: ssh.socket is the listener and the Port
# directive in sshd_config is ignored entirely. Override the socket's
# ListenStream to match.
if systemctl is-active --quiet ssh.socket 2>/dev/null; then
  mkdir -p /etc/systemd/system/ssh.socket.d
  cat > /etc/systemd/system/ssh.socket.d/listen.conf <<'SOCKCONF'
[Socket]
ListenStream=
ListenStream=50022
SOCKCONF
  systemctl daemon-reload
  systemctl restart ssh.socket
elif systemctl is-active --quiet ssh.service 2>/dev/null; then
  systemctl restart ssh.service
elif systemctl is-active --quiet sshd.service 2>/dev/null; then
  systemctl restart sshd.service
else
  echo "ERROR: neither ssh.socket nor ssh.service nor sshd.service is active — can't apply Port 50022." >&2
  exit 1
fi

# Verify sshd actually bound 50022 before declaring success. Without
# this, a half-hardened VPS — nftables on 50022, nothing listening,
# sentinel set, script exits 0 — locks out the next ssh attempt with
# no signal that anything went wrong. ss's native filter is more
# precise than a regex over its tabular output.
#
# Poll for up to 10s. Restart-to-listen on modern systemd is typically
# sub-second, but `Type=notify` ssh.service can occasionally lag if
# the host is under load (first boot, apt activity, etc.).
listening=
for _ in $(seq 1 10); do
  if ss -tln 'sport = :50022' | grep -q LISTEN; then
    listening=1
    break
  fi
  sleep 1
done
if [ -z "$listening" ]; then
  echo "ERROR: sshd did not bind 50022 within 10s of restart." >&2
  echo "  Sentinel NOT touched — re-run the script after fixing the issue." >&2
  echo "  Debug: systemctl status ssh.service ssh.socket; journalctl -u ssh.service -n 50" >&2
  echo "  Recover via the still-open ssh session, OVH manager console, or rescue mode." >&2
  exit 1
fi

touch /etc/tayaway/sshd-hardened.done
echo "ssh hardening complete — port 50022, AllowUsers tayaway ubuntu."
EOF

  cat <<NOTICE

──────────────────────────────────────────────────────────────────────
  SSH is now on port 50022. AllowUsers permits 'tayaway' and 'ubuntu'
  (ubuntu kept as fallback). Update ~/.ssh/config so subsequent runs
  find the new port:

    Host new.tayaway.nl
      Port 50022
      User tayaway
      IdentityFile ~/.ssh/id_ed25519

  For the ubuntu fallback: ssh ubuntu@<host> -p 50022 still works.

  Your CURRENT ssh session is still alive (sshd reload preserved it),
  but ANY NEW ssh attempt without the new port will fail.
──────────────────────────────────────────────────────────────────────
NOTICE
fi

echo
echo "✓ Provision complete for $TARGET"
