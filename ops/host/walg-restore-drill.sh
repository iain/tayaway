#!/usr/bin/env bash
#
# Monthly restore drill: prove the WAL-G backups are actually restorable —
# the whole reason WAL-G replaces the old nightly dump. Fetches the LATEST
# base backup into a throwaway postgres container, replays WAL from object
# storage to a consistent point, promotes, and runs a sanity query. On
# failure the unit's OnFailure= pages via ntfy.
#
# Touches NOTHING in production: a separate, --rm container with its own
# ephemeral data dir (never the tayaway-db.volume), archive_mode off (so it
# can't push WAL), and an unpublished port. It only *reads* from the backup
# bucket, exactly as a real restore would.
set -euo pipefail

DRILL_NAME=walg-restore-drill-run
ENVFILE=/run/tayaway/db.env

# Use the exact image the prod db is running, so wal-g + postgres versions
# match the cluster that produced the backups.
IMAGE=$(podman inspect db --format '{{.ImageName}}')
echo "[drill] using db image: $IMAGE"

# Join the same podman network as db for working DNS + S3 egress. Quadlet
# creates the network under a generated name (systemd-tayaway), not the
# literal "tayaway.network" the .container files reference, so derive the
# real name from the running db container rather than hardcoding it.
NET=$(podman inspect db --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')
echo "[drill] using network: $NET"

# A wedged previous run would hold the name; clear it first.
podman rm -f "$DRILL_NAME" >/dev/null 2>&1 || true

# --env-file carries the S3 keypair + libsodium key (from the host decrypt
# oneshot); the -e values mirror the non-secret WAL-G config that
# db.container sets. WALG_LIBSODIUM_KEY_TRANSFORM=hex is load-bearing: the
# key is stored hex, and without it wal-g can't decrypt the backup.
podman run --rm -i --name "$DRILL_NAME" \
  --network "$NET" \
  --pull=never \
  --env-file "$ENVFILE" \
  -e WALG_S3_PREFIX=s3://tayaway-walg \
  -e AWS_ENDPOINT=https://s3.gra.io.cloud.ovh.net \
  -e AWS_REGION=gra \
  -e WALG_LIBSODIUM_KEY_TRANSFORM=hex \
  --entrypoint /bin/bash \
  "$IMAGE" -s <<'INNER'
set -euo pipefail
DATADIR=/tmp/restore
LOG=/tmp/restore-pg.log

rm -rf "$DATADIR"
install -d -o postgres -g postgres -m 700 "$DATADIR"

echo "[drill] fetching LATEST base backup"
runuser -u postgres -- wal-g backup-fetch "$DATADIR" LATEST

echo "[drill] configuring WAL replay to first-consistent point"
runuser -u postgres -- touch "$DATADIR/recovery.signal"
cat >> "$DATADIR/postgresql.auto.conf" <<CONF
restore_command = 'wal-g wal-fetch %f %p'
recovery_target = 'immediate'
recovery_target_action = 'promote'
archive_mode = off
CONF
chown postgres:postgres "$DATADIR/postgresql.auto.conf"

echo "[drill] starting postgres to replay WAL"
if ! runuser -u postgres -- pg_ctl -D "$DATADIR" -w -t 280 -l "$LOG" \
     -o "-c listen_addresses=127.0.0.1 -c port=5433 -c archive_mode=off" start; then
  echo "[drill] postgres failed to reach a consistent state; server log:" >&2
  cat "$LOG" >&2 || true
  exit 1
fi

echo "[drill] sanity query"
# Connect as the cluster superuser. The restored cluster's roles come from
# prod, where POSTGRES_USER=tayaway — there is no "postgres" role, so the
# psql default (role = OS user "postgres") would fail with "role does not
# exist". Local socket is trust auth, so no password needed.
tables=$(runuser -u postgres -- psql -U tayaway -p 5433 -d tayaway -tAc \
  "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'")

runuser -u postgres -- pg_ctl -D "$DATADIR" -m immediate stop >/dev/null 2>&1 || true

echo "[drill] recovered cluster exposes ${tables} public tables"
# A real restore of the tayaway schema has dozens of tables; an empty
# cluster (failed/garbage restore) has zero. Anything >0 proves the base
# backup + WAL fetch + replay round-trip actually works.
test "${tables:-0}" -ge 1
INNER

echo "[drill] restore drill passed"
