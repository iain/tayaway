#!/usr/bin/env bash
#
# Decrypt POSTGRES_PASSWORD from the sops-encrypted production env and
# write it to /run/tayaway/db.env (tmpfs, root-only) for db.container's
# EnvironmentFile. Run by tayaway-db-secret.service as a host oneshot,
# ordered before db.service.
#
# The stock postgres image has no mise/sops, so it can't decrypt the
# yaml itself — this bridges that. Decrypting on the host (rather than
# in a helper container) keeps the age key off every container: only
# /etc/tayaway/age.key on the host ever reads it for the database path.
# web/migrate still decrypt in-process via mise; this covers db alone.
#
# POSTGRES_PASSWORD only matters at first-init (postgres bakes it into
# the role on an empty data dir, ignores it after), but regenerating
# the file each boot is cheap and keeps /run self-healing.
set -euo pipefail

ENV_YAML=/etc/tayaway/env/.env.production.yaml
OUT=/run/tayaway/db.env

install -d -m 0700 /run/tayaway

pw=$(SOPS_AGE_KEY_FILE=/etc/tayaway/age.key \
  sops decrypt --extract '["POSTGRES_PASSWORD"]' "$ENV_YAML")

umask 077
printf 'POSTGRES_PASSWORD=%s\n' "$pw" > "$OUT"
echo "wrote POSTGRES_PASSWORD to $OUT"
