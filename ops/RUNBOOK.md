# Runbook

Day-to-day operations and emergency procedures for the tayaway production
stack (podman + Quadlet on a single OVH VPS). For **first-time bring-up** and
**total-loss rebuild**, see [`README.md`](README.md) — this file assumes the
stack already exists and you need to operate or repair it.

Conventions:

- **From your laptop** (in the repo): `mise run deploy …`, `mise run vm:provision …`, `tofu …`.
- **On the box**: everything else. SSH in with `ssh new.tayaway.nl` (port 50022, user `tayaway`, set up in `~/.ssh/config` — see README step 7). Almost everything needs `sudo` (rootful podman + system units).
- `$HOST` below means the box's public name — `new.tayaway.nl` during commissioning, `tayaway.nl` after cutover.

---

## 1. System at a glance

Five containers, supervised by systemd via Quadlet units in
`/etc/containers/systemd/`. Quadlet generates a `*.service` per `*.container`.

| Service           | Kind     | What it is                                                        |
| ----------------- | -------- | ----------------------------------------------------------------- |
| `db`              | running  | PostgreSQL 18 + wal-g. Data in the `tayaway-db` volume.           |
| `web`             | running  | Falcon backend. `Notify=true` — restart completes only when ready.|
| `edge`            | running  | Caddy: TLS, serves the SPA, proxies `/api` `/ws` `/health` → web. |
| `migrate`         | oneshot  | `rake config:validate db:migrate`, runs before `web` on each start.|
| `geoip`           | oneshot  | Loads the GeoIP db into the `tayaway-geoip` volume.               |

Host units (`/etc/systemd/system/`):

| Unit                          | Schedule / trigger        | Purpose                                  |
| ----------------------------- | ------------------------- | ---------------------------------------- |
| `tayaway-db-secret.service`   | boot, before `db`         | Decrypts DB/WAL-G secrets → `/run/tayaway/db.env` (tmpfs) |
| `walg-backup.timer`           | daily 02:30               | `wal-g backup-push` (weekly full + deltas)|
| `walg-retain.timer`           | Mon 04:00                 | `wal-g delete retain FULL 4` (~1mo PITR) |
| `walg-restore-drill.timer`    | 5th 05:00                 | Restore latest backup in a throwaway container; alert on failure |
| `geoip.timer`                 | 3rd 04:00                 | Monthly GeoIP refresh                    |
| `notify@.service`             | via `OnFailure=`          | Posts a failed unit name to ntfy (template) |

Plus **continuous WAL archiving** (`archive_command = wal-g wal-push`, runs
inside `db` independently of the timers).

**Key paths (on the box):**

| Path                                   | What                                              |
| -------------------------------------- | ------------------------------------------------- |
| `/etc/containers/systemd/`             | Quadlet units (synced from repo `ops/quadlet/`)   |
| `/etc/tayaway/age.key`                 | Production age key (0400 root) — decrypts secrets |
| `/etc/tayaway/env/.env.production`      | Non-secret config (plain dotenv)                  |
| `/etc/tayaway/env/.env.production.yaml` | sops-encrypted secrets                            |
| `/run/tayaway/db.env`                  | Decrypted DB/WAL-G secrets (tmpfs, per-boot)      |

**Volumes:** `tayaway-db` (Postgres data — the precious one),
`tayaway-geoip` (GeoIP db), `tayaway-caddy` (ACME account + LE certs).
**Network:** `systemd-tayaway` (containers reach each other by name: `db:5432`, `web:9292`).
**Backups:** `s3://tayaway-walg` (OVH Object Storage, encrypted with `WALG_LIBSODIUM_KEY`).

---

## 2. Health & status — run these first

```bash
# From anywhere — the single best "is it up?" signal (does a real DB ping):
curl -fsS https://$HOST/health        # → {"status":"healthy"}

# On the box:
systemctl --failed                    # anything broken?
systemctl status db web edge --no-pager
sudo podman ps -a                     # container states (db should be "healthy")
systemctl list-timers --no-pager      # backups/geoip armed and next-run sane?
df -h /                               # disk (the silent killer)
```

---

## 3. Normal operations

### Deploy a new version

From your laptop, after the App-images workflow has built the SHA (push to
`main` triggers it):

```bash
mise run deploy tayaway@new.tayaway.nl            # deploys HEAD
mise run deploy tayaway@new.tayaway.nl <git-sha>  # or a specific SHA
```

This pulls the `backend`/`edge`/`geoip` images, rewrites their tags in the
quadlets + `images.txt`, restarts `migrate → web → edge` in order, and polls
`/health` — **auto-rolling-back to the previous SHA if it doesn't go green**.
`db` is never touched. After a green deploy, commit the SHA bump in `ops/` for
history (optional — the working tree and the box already agree).

### Roll back a deploy

The deploy auto-rolls-back on a failed `/health`. To roll back *after* a
deploy that went green but is misbehaving, just deploy the last-good SHA:

```bash
mise run deploy tayaway@new.tayaway.nl <last-good-sha>
```

Safe because all migrations are additive (see `doc/database-migrations.md`) —
old code runs against the newer schema. If that rule is ever broken, SHA
rollback is no longer safe.

### Apply an ops/config change (quadlets, host units, env, firewall)

Edit under `ops/`, then re-run the idempotent provisioner from your laptop:

```bash
mise run vm:provision tayaway@new.tayaway.nl
```

It syncs `ops/quadlet/` and `ops/host/`, delivers the env files,
`daemon-reload`s, `enable --now`s the timers, and re-pulls images. It does
**not** restart running app containers — do that explicitly if a quadlet
changed:

```bash
ssh new.tayaway.nl 'sudo systemctl restart web edge'
```

### Restart / stop / start a service

```bash
ssh new.tayaway.nl 'sudo systemctl restart web'      # one service
ssh new.tayaway.nl 'sudo systemctl stop edge web'    # take the site offline
ssh new.tayaway.nl 'sudo systemctl start edge'       # pulls web→migrate→db via deps
```

After a service hits its crash-loop limit (`StartLimitBurst=3` in 60s) systemd
refuses to start it until you clear the failure:

```bash
ssh new.tayaway.nl 'sudo systemctl reset-failed web && sudo systemctl start web'
```

### Logs

```bash
ssh new.tayaway.nl 'sudo journalctl -u web -n 200 --no-pager'   # recent
ssh new.tayaway.nl 'sudo journalctl -u web -f'                  # follow
ssh new.tayaway.nl 'sudo journalctl -u edge -f'                 # Caddy access log (JSON)
ssh new.tayaway.nl 'sudo journalctl -u db --since "30 min ago"'
```

### Database console

```bash
ssh new.tayaway.nl 'sudo podman exec -it db psql -U tayaway -d tayaway'
```

### Backups

```bash
# List what's in the bucket:
ssh new.tayaway.nl 'sudo podman exec db wal-g backup-list'

# Take a backup right now (also re-arms confidence after a manual change):
ssh new.tayaway.nl 'sudo systemctl start walg-backup.service'

# Prove a backup is actually restorable, on demand (throwaway container,
# touches nothing in prod):
ssh new.tayaway.nl 'sudo systemctl start walg-restore-drill.service'
ssh new.tayaway.nl 'sudo journalctl -u walg-restore-drill -n 20 --no-pager'
#   → "[drill] recovered cluster exposes N public tables" / "restore drill passed"

# Is continuous WAL archiving healthy? (failed should be 0)
ssh new.tayaway.nl "sudo podman exec db psql -U tayaway -d tayaway -tAc \
  'SELECT archived_count, failed_count, last_archived_time FROM pg_stat_archiver;'"
```

### Refresh GeoIP now

```bash
ssh new.tayaway.nl 'sudo systemctl start geoip.service'
# web picks up the new file on its next lookup (mtime cache) — no restart.
```

### Rotate a secret

Edit the encrypted file on your laptop, re-deliver, restart what reads it.
`POSTGRES_PASSWORD` and `APP_SECRET` have extra steps — see the rotation
playbook in issue #440 (Phase 10). The general shape:

```bash
mise x sops -- sops backend/.env.production.yaml   # edit + re-encrypt on save
mise run vm:provision tayaway@new.tayaway.nl       # redeliver to /etc/tayaway/env
ssh new.tayaway.nl 'sudo systemctl restart tayaway-db-secret web migrate'
```

---

## 4. Emergencies

### Site is down

Triage from the outside in — find the layer that breaks:

```bash
curl -v https://$HOST/health
```

| Symptom                              | Likely cause            | Next step                                            |
| ------------------------------------ | ----------------------- | ---------------------------------------------------- |
| DNS doesn't resolve                  | DNS / OVH               | Check `ops/dns.tf` / OVH console; recent cutover?    |
| Connection refused / timeout         | `edge` down or host/fw  | SSH in (below). If SSH also dead → OVH console/reboot.|
| TLS error                            | Cert / Caddy            | See "TLS problems" below                             |
| `502`/`503` from Caddy               | `web` down or unhealthy | SSH in, check `web` and `db`                         |
| `200` but app misbehaves             | app bug / bad deploy    | Roll back (§3); check `web` logs                     |

Then on the box:

```bash
systemctl --failed
systemctl status edge web db migrate --no-pager
sudo journalctl -u web -n 100 --no-pager
df -h /                               # full disk breaks almost everything
```

Restart the broken layer; if it crash-looped, `reset-failed` first (§3).

### `web` crash-looping

```bash
sudo journalctl -u web -n 200 --no-pager     # find the boot error
```

Common causes: a migration failed (check `migrate`), a bad secret/env
(`config:validate` rejects it), or a bad image. If it's a bad deploy, roll
back (§3). After fixing the root cause:

```bash
sudo systemctl reset-failed web && sudo systemctl start web
```

### `db` won't start

```bash
sudo journalctl -u db -n 100 --no-pager
sudo systemctl status tayaway-db-secret --no-pager   # did secrets decrypt?
ls -l /run/tayaway/db.env                            # exists? (regenerated per boot)
```

If `db.env` is missing/empty, the age key or encrypted env is the problem:
`ls -l /etc/tayaway/age.key /etc/tayaway/env/`. Re-run
`tayaway-db-secret.service` after fixing:

```bash
sudo systemctl restart tayaway-db-secret && sudo systemctl restart db
```

If the data volume is corrupt, go to **Restore from backup**.

### Disk full

```bash
df -h / ; sudo du -xh --max-depth=1 / 2>/dev/null | sort -rh | head
sudo journalctl --disk-usage
sudo journalctl --vacuum-size=500M           # trim logs (cap is 2G/30d)
sudo podman image prune -f                   # remove dangling/unused images
sudo podman images                           # then remove old app SHAs by hand:
# sudo podman rmi ghcr.io/iain/tayaway-backend:<old-sha>
```

### Backups failing / WAL archiving stuck

An alert fires (`walg-backup.service` `OnFailure`) or `failed_count` climbs in
`pg_stat_archiver`.

```bash
sudo journalctl -u walg-backup -n 50 --no-pager
sudo podman exec db sh -c 'wal-g wal-push /var/lib/postgresql/18/docker/pg_wal/$(ls -t /var/lib/postgresql/18/docker/pg_wal | head -1)' 2>&1 | tail
```

Usual culprits: expired/rotated S3 credentials (check `/run/tayaway/db.env`
has `AWS_ACCESS_KEY_ID`; re-run `tayaway-db-secret` after fixing the sops
file), or the bucket/endpoint unreachable. **Continuous archiving retries on
its own** — Postgres keeps the WAL and re-runs `archive_command`, so a
transient failure self-heals once the cause is fixed.

### Restore from backup (latest) — ⚠️ destructive, overwrites the DB

The monthly drill rehearses exactly this against a throwaway container; this
is the same flow targeting the **real** data volume. Confirm `PGDATA` first
(it's a versioned subdir under the volume):

```bash
sudo podman exec db printenv PGDATA          # e.g. /var/lib/postgresql/18/docker
```

```bash
# 1. Stop writers, the db, and the backup timers (so nothing fights the restore).
sudo systemctl stop edge web
sudo systemctl stop walg-backup.timer walg-retain.timer walg-restore-drill.timer
sudo systemctl stop db

# 2. Fetch the latest base backup into the data volume + arm WAL replay.
#    Uses the same image + secrets the db runs with.
DBIMG=$(grep -oE 'ghcr.io/iain/tayaway-db:[0-9a-f]+' /etc/containers/systemd/db.container)
sudo podman run --rm -i \
  --network systemd-tayaway \
  --env-file /run/tayaway/db.env \
  -e WALG_S3_PREFIX=s3://tayaway-walg \
  -e AWS_ENDPOINT=https://s3.gra.io.cloud.ovh.net -e AWS_REGION=gra \
  -e WALG_LIBSODIUM_KEY_TRANSFORM=hex \
  -v tayaway-db:/var/lib/postgresql \
  --entrypoint /bin/bash "$DBIMG" -s <<'EOF'
set -euo pipefail
PGDATA=/var/lib/postgresql/18/docker
rm -rf "$PGDATA"
install -d -o postgres -g postgres -m 700 "$PGDATA"
runuser -u postgres -- wal-g backup-fetch "$PGDATA" LATEST
runuser -u postgres -- touch "$PGDATA/recovery.signal"
printf "restore_command = 'wal-g wal-fetch %%f %%p'\n" >> "$PGDATA/postgresql.auto.conf"
chown postgres:postgres "$PGDATA/postgresql.auto.conf"
EOF

# 3. Start the db — it replays WAL from object storage, then promotes.
sudo systemctl start db
sudo journalctl -u db -f        # wait for "database system is ready to accept connections"

# 4. Bring the site back, re-arm timers, and take a fresh base backup
#    (recovery starts a new timeline).
sudo systemctl start edge web
sudo systemctl start walg-backup.timer walg-retain.timer walg-restore-drill.timer
curl -fsS https://$HOST/health
sudo systemctl start walg-backup.service
```

### Point-in-time restore (PITR)

Same as above, but in step 2 add a target so replay stops at a chosen instant
(e.g. just before a bad migration or a fat-fingered delete):

```bash
# append inside the heredoc's postgresql.auto.conf block:
printf "recovery_target_time = '2026-05-26 11:55:00+00'\n" >> "$PGDATA/postgresql.auto.conf"
printf "recovery_target_action = 'promote'\n"             >> "$PGDATA/postgresql.auto.conf"
```

Retention keeps ~1 month of PITR window (last 4 full backups). Pick a time
within that window and after the oldest retained base backup.

### TLS / certificate problems

Caddy auto-manages Let's Encrypt certs in the `tayaway-caddy` volume.

```bash
sudo journalctl -u edge | grep -iE 'acme|certificate|tls' | tail -30
echo | openssl s_client -connect $HOST:443 -servername $HOST 2>/dev/null | openssl x509 -noout -issuer -dates
```

Don't delete the `tayaway-caddy` volume to "fix" certs — you'll re-request
from LE and can trip rate limits. If you suspect a corrupt ACME state, restart
`edge` first and watch the log.

### Locked out of SSH

`ubuntu` is kept as an emergency fallback user (`AllowUsers tayaway ubuntu`,
port 50022). If `tayaway`'s key fails:

```bash
ssh ubuntu@$HOST -p 50022
```

If both fail, use **OVH manager → rescue mode** (or the KVM console) to fix
`sshd`/`nftables`. The hardening step verifies sshd bound 50022 before locking
in, so a half-applied state shouldn't strand you — but keep a second session
open whenever you re-provision.

### Total host loss

The VPS is gone. Follow **Total-loss recovery** in [`README.md`](README.md):
re-point DNS + recreate WAL-G creds with `tofu apply`, order a VPS,
`vm:provision` twice, drop the age key, then **Restore from backup** above.
~20 minutes plus the OVH order.

---

## 5. What pages you

`OnFailure=notify@%n.service` on `db`, `web`, `edge`, `migrate`, and the WAL-G
backup/retain/restore-drill units posts to an ntfy topic (the `NTFY_TOPIC`
secret) when a unit fails — including after a crash-loop gives up. Subscribe
to that topic in the ntfy app/web to receive alerts.

> **Caveat:** the topic is on ntfy.sh's free tier, which rate-limits (HTTP
> 429) under bursts. Rare real failures get through; if you start relying on
> this for real paging, move to a paid or self-hosted ntfy topic.

Test the path (will itself be rate-limited if you hammer it):

```bash
ssh new.tayaway.nl 'sudo systemctl start notify@manual-test.service'
```

---

## 6. Reference

**Timer schedule (UTC):** backup daily 02:30 · retain Mon 04:00 · GeoIP 3rd
04:00 · restore-drill 5th 05:00. All `Persistent=true` (a missed run while the
box was down fires on next boot) with a randomized delay.

**Image SHAs:** pinned in `ops/quadlet/*.container` and `ops/images.txt`.
`backend`/`edge`/`geoip` share the app commit SHA and move together via
`deploy`; `db` has its own SHA (rebuilt only when `Containerfile.db` or the
wal-g version changes).

**Firewall:** nftables, inbound `50022` (ssh) + `80`/`443` only; outbound open.
`sudo nft list ruleset`.

**Won't restart the app:** `vm:provision` syncs + reloads but deliberately
leaves running containers alone. **Will restart the app:** `deploy` (migrate →
web → edge) and any explicit `systemctl restart`.
