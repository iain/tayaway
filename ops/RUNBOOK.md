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

### Continuous deployment (pull-based)

Merges to `main` deploy themselves — **no human step, and GitHub has no access
to the box**. `images.yml` builds and pushes a moving `:main` tag; on the box,
`self-deploy.timer` runs `self-deploy.sh` every ~3 min, which resolves `:main`
→ its commit SHA (via the image's `revision` label), and if it's newer than
what's running, pulls + restarts migrate→web→edge + smoke-tests `/health` +
confirms the new image is live — **rolling back on any failure**. So expect a
few minutes' lag from merge to live.

```bash
# Force a check now (don't wait for the timer):
ssh new.tayaway.nl 'sudo systemctl start self-deploy.service'
ssh new.tayaway.nl 'sudo journalctl -u self-deploy -n 50 --no-pager'

# Pause / resume CD (e.g. before a manual pin, or during an incident):
ssh new.tayaway.nl 'sudo systemctl stop --now self-deploy.timer'   # pause
ssh new.tayaway.nl 'sudo systemctl start self-deploy.timer'        # resume
```

A failed self-deploy rolls back and writes the bad SHA to
`/var/lib/tayaway/self-deploy-last-bad`, so the timer won't re-attempt it — it
sits on the last-good image until a **new** SHA appears (a fix-forward commit
clears it automatically). It also pages via ntfy (`OnFailure=`).

**Manual deploy / rollback overrides CD only if you pause the timer first** —
otherwise the next tick re-advances the box to `:main`. To pin an older SHA:

```bash
ssh new.tayaway.nl 'sudo systemctl stop --now self-deploy.timer'
mise run deploy tayaway@new.tayaway.nl <last-good-sha>
# resume CD once main is fixed-forward past the bad SHA
```

`main`'s committed SHA pins drift behind the live box (pull-based deploys don't
commit). That's cosmetic — the box self-heals to `:main` even after a
`vm:provision` — and the weekly **Reconcile deployed image SHA** workflow opens
a PR to catch the pins up; merge it when convenient. If the box's GHCR login
lapses (e.g. after a rebuild), self-deploy can't pull and pages — re-run
`vm:provision` to re-establish it.

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

---

## 7. Cutover (old box → new box, the one-time apex flip)

Moving production `tayaway.nl` off the old Capistrano VPS (`51.195.43.146`)
onto the new podman box (`new.tayaway.nl` = `51.178.47.84` / `…:2460`). It is
**more than the DNS flip** — three things move together: the database, the
apex A/AAAA records, and the edge's `SITE_ADDRESS` (which is what makes Caddy
get the apex TLS cert). Do them in the order below; the ordering around TLS is
not optional.

Run everything from your laptop in `ops/` (tofu reads creds from
`secrets.yaml`). Expect **~10–15 min of downtime** for the final DB copy +
propagation.

### Preconditions (all done as of 2026-05-27)

- Apex TTL is **300** (lowered ≥24 h earlier so the flip propagates in minutes;
  see §3 "Apply an ops/config change" + `ops/dns.tf`). Confirm it has aged out:
  `dig +short tayaway.nl @ns14.ovh.net` and check the TTL is 300, not 3600.
- New box verified: `/health` 200, **IPv6 serving** (`curl -6
  https://new.tayaway.nl/health` → 200), WAL-G archiving healthy
  (`failed_count = 0`), restore drill green, login email delivers (jobs worker).
- Backend needs **no** config change: `FRONTEND_URL` is already
  `https://tayaway.nl`, so email links, WebAuthn `rp_id`, and CSP origins are
  all apex-keyed. Passkeys and login-link click-through only work *after*
  cutover (they're bound to the apex), so don't be alarmed they fail on
  `new.tayaway.nl` beforehand.

### The cutover

```bash
# 1. Stop the OLD box's app so no new writes land and any queued emails/push
#    freeze in its async_jobs table (they'll send exactly once from the new
#    box after the restore — not zero, not twice). Old DB keeps running for
#    the dump. The old box runs a single `tayaway-falcon.service` (web + the
#    in-process jobs worker — no separate worker unit), fronted by nginx;
#    stopping it freezes writes and any queued async_jobs.
ssh tayaway.nl 'sudo systemctl stop tayaway-falcon'   # site now 502s via nginx

# 2. Final dump of the old prod DB → restore into the new box's db container.
#    Both sides are PG 18.3, DB ~11 MB. Dump AS the `tayaway` ssh user via peer
#    auth — NOT `sudo -u postgres` (the old box only grants `tayaway` NOPASSWD
#    sudo for the `tayaway-falcon` unit, so `sudo -u postgres` is refused). The
#    app's DATABASE_URL is a unix-socket peer-auth conn, so plain pg_dump works.
#    New cluster uses role `tayaway` (no `postgres` role there).
ssh tayaway.nl 'pg_dump -Fc tayaway_production' > /tmp/prod.dump
#    Recreate the target so the new box's commissioning/test data is gone. Stop
#    web first so the DB has no app connections; WITH (FORCE) drops any leftover.
ssh new.tayaway.nl 'sudo systemctl stop web'
ssh new.tayaway.nl 'sudo podman exec -i db psql -U tayaway -d postgres' <<'SQL'
DROP DATABASE IF EXISTS tayaway WITH (FORCE);
CREATE DATABASE tayaway OWNER tayaway;
SQL
ssh new.tayaway.nl 'sudo podman exec -i db pg_restore -U tayaway -d tayaway \
  --no-owner --no-privileges' < /tmp/prod.dump
#    (step 3's `restart migrate web` brings web back up on the restored DB)

# 3. Re-run migrate + restart web so it binds the restored DB and the jobs
#    worker starts draining the imported async_jobs (queued emails go out now).
ssh new.tayaway.nl 'sudo systemctl restart migrate web'
ssh new.tayaway.nl 'sudo podman exec db psql -U tayaway -d tayaway -tAc \
  "select count(*) from users;"'   # sanity: row counts match old prod

# 4. Fresh base backup — recovery/restore starts a new baseline.
ssh new.tayaway.nl 'sudo systemctl start walg-backup.service'

# 5. Flip the apex DNS to the new box. Edit ops/variables.tf defaults:
#      apex_ipv4 = "51.178.47.84"
#      apex_ipv6 = "2001:41d0:404:200::2460"
#    (keeping config = live keeps the drift check green), then:
mise exec -- tofu apply        # review: only apex_a + apex_aaaa target changes
dig +short tayaway.nl @ns14.ovh.net          # poll until it shows the new IP

# 6. ONLY after the apex resolves to the new box: flip the edge so Caddy
#    serves tayaway.nl and provisions its LE cert (it can't until DNS points
#    here — HTTP-01/TLS-ALPN). In ops/quadlet/edge.container set
#      SITE_ADDRESS=https://tayaway.nl
#    and delete the EXTRA_CONNECT_SRC line, then:
mise run vm:provision tayaway@new.tayaway.nl
ssh new.tayaway.nl 'sudo systemctl restart edge'
ssh new.tayaway.nl 'sudo journalctl -u edge -f'   # watch for the cert, then ^C
```

### Verify

```bash
curl -sS https://tayaway.nl/health                       # 200, valid apex cert
curl -6 -sS https://tayaway.nl/health                    # 200 over IPv6
```

Then in a browser on `tayaway.nl`: log in via email link (full click-through
now works), and confirm an existing **passkey** authenticates (proves the
migrated WebAuthn credentials + apex origin line up). There may be a sub-minute
TLS blip on step 6 while Caddy fetches the cert — normal.

### Rollback (apex back to the old box, ~5 min at TTL 300)

If anything's wrong, revert the apex targets and re-apply — the old box is
untouched and still serving:

```bash
git checkout ops/variables.tf      # restore apex_ipv4/apex_ipv6 to the old box
mise exec -- tofu apply
ssh tayaway.nl 'sudo systemctl start tayaway-falcon'   # if you stopped it
```

Caveat: any writes made on the new box after cutover won't be on the old box.
Rolling back is clean only in the first minutes, before real traffic lands.

### After it's settled (keep the old box warm ~1 week, then decommission)

**DNS cleanup** — one coordinated `tofu apply` so the drift check stays green:

- Remove the `new.tayaway.nl` A/AAAA records (`ovh_domain_zone_record.new_a` /
  `new_aaaa` in `ops/dns.tf`).
- Repoint or drop **`www.tayaway.nl`**. It is NOT tofu-managed and still points
  at the OLD box (`A → 51.195.43.146`), so it breaks when the box dies. Either
  bring it into `ops/dns.tf` aimed at the new box **and** add a `www`→apex
  redirect block to the edge Caddyfile, or delete the record if www is unused.
- Optionally raise `apex_ttl` back to `0` (zone default 3600) now the flip is
  done.
- Drop `EXTRA_CONNECT_SRC` for good (already removed from the env at step 6;
  delete any dangling reference/comment in `edge.container`).

**Decommission the old VPS:**

- Confirm nothing else points at it. Repo, CI, and Terraform are clean (the VPS
  isn't in tofu); the only OVH-zone straggler is the `www` record above. Re-list
  the zone read-only with an OVH-API `GET /domain/zone/tayaway.nl/record` (ops
  creds, signed) or eyeball it in the manager.
- Optional insurance: a final cold `pg_dump` off the old box — `ssh
  tayaway@51.195.43.146 -p 50022`, peer-auth `pg_dump -Fc tayaway_production` —
  stashed off-box, since the disk is unrecoverable once the VPS is cancelled.
- Check the old box's nginx logs for residual stale-DNS traffic; wait for ~zero.
- **Terminate** the VPS in the OVH manager. It is NOT in Terraform (ordered
  through the manager), so there is no `tofu destroy`. A fixed monthly VPS keeps
  billing when merely powered off — you must *cancel/terminate the subscription*
  to stop the charge.
