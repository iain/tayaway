#!/usr/bin/env bash
#
# Decrypt the db container's secrets from the sops production env into
# /run/tayaway/db.env (tmpfs, root-only) for db.container's EnvironmentFile.
# Run by tayaway-db-secret.service as a host oneshot, ordered before
# db.service.
#
# Covers POSTGRES_PASSWORD (postgres auth) plus the WAL-G secrets the
# archive_command + backup timers need: the bucket S3 keypair (written under
# the AWS_* names wal-g and the S3 SDK expect) and the libsodium key.
# Decrypting on the host keeps the age key off every container — only
# /etc/tayaway/age.key reads it, for the db path. web/migrate decrypt
# in-process via mise; this covers db alone.
#
# POSTGRES_PASSWORD only matters at first-init; the WAL-G keys are read on
# every archive_command / backup run. Regenerating the file each boot is
# cheap and keeps /run self-healing.
set -euo pipefail

ENV_YAML=/etc/tayaway/env/.env.production.yaml
OUT=/run/tayaway/db.env
AGE=/etc/tayaway/age.key

extract() { # key -> value on stdout, empty if the key is absent
  SOPS_AGE_KEY_FILE="$AGE" sops decrypt --extract "[\"$1\"]" "$ENV_YAML" 2>/dev/null || true
}

install -d -m 0700 /run/tayaway

pw=$(extract POSTGRES_PASSWORD)
[ -n "$pw" ] || { echo "POSTGRES_PASSWORD missing from $ENV_YAML" >&2; exit 1; }

# WAL-G secrets are optional: absent just means archiving/backups aren't
# configured yet, which degrades gracefully (postgres keeps WAL and retries)
# rather than blocking the database from starting.
walg_ak=$(extract WALG_S3_ACCESS_KEY_ID)
walg_sk=$(extract WALG_S3_SECRET_ACCESS_KEY)
walg_key=$(extract WALG_LIBSODIUM_KEY)

umask 077
{
  printf 'POSTGRES_PASSWORD=%s\n' "$pw"
  [ -n "$walg_ak" ]  && printf 'AWS_ACCESS_KEY_ID=%s\n' "$walg_ak"
  [ -n "$walg_sk" ]  && printf 'AWS_SECRET_ACCESS_KEY=%s\n' "$walg_sk"
  [ -n "$walg_key" ] && printf 'WALG_LIBSODIUM_KEY=%s\n' "$walg_key"
} > "$OUT"

echo "wrote db.env: POSTGRES_PASSWORD${walg_ak:+ + WAL-G S3 creds}${walg_key:+ + libsodium key}"
