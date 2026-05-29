#!/bin/bash
# Daily encrypted PostgreSQL backup for Tayaway.
#
# Runs as the `tayaway` system user via cron. pg_dump connects via the
# DATABASE_URL in the app's .env.production — a Unix-socket peer-auth
# URL — so the OS user invoking this script is the Postgres role it
# dumps as. Same connection the running app uses, no separate
# credentials to manage.
#
# Setup (one-time, on the server, as the tayaway user):
#   1. Generate a backup encryption key:
#      openssl rand -base64 32 > /var/www/tayaway/shared/.backup-key
#      chmod 600 /var/www/tayaway/shared/.backup-key
#
#   2. Create the backup directory:
#      mkdir -p /var/www/tayaway/shared/backups
#
#   3. Add cron job (daily at 3am) to the tayaway user's crontab:
#      crontab -e
#      0 3 * * * /var/www/tayaway/current/config/deploy/backup-db.sh >> /var/www/tayaway/shared/log/backup.log 2>&1
#
# Restore (emergency, run as the postgres superuser since plain dumps may
# include CREATE EXTENSION or owner reassignments the app role cannot do):
#   openssl enc -d -aes-256-cbc -salt -pbkdf2 \
#     -pass file:/var/www/tayaway/shared/.backup-key \
#     -in /var/www/tayaway/shared/backups/tayaway-20260404-030000.sql.gz.enc \
#     | gunzip | sudo -u postgres psql tayaway_production
#
# This script trusts pg_dump's exit status (via `set -o pipefail`) — it
# does not re-read the encrypted file to verify it round-trips. Backups
# you cannot restore are worse than no backups, so periodically (monthly
# is fine) restore the latest dump into a scratch database and confirm
# the row counts match production. That's the only verification that
# actually proves recoverability.
#
set -euo pipefail

ENV_FILE="/var/www/tayaway/shared/backend/.env.production"
BACKUP_DIR="/var/www/tayaway/shared/backups"
KEY_FILE="/var/www/tayaway/shared/.backup-key"
RETENTION_DAYS=30

if [ ! -f "$KEY_FILE" ]; then
  echo "ERROR: Backup key not found at $KEY_FILE" >&2
  echo "Generate one with: openssl rand -base64 32 > $KEY_FILE && chmod 600 $KEY_FILE" >&2
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: Env file not found at $ENV_FILE" >&2
  exit 1
fi

# Load DATABASE_URL from the app's env file. `set -a` exports every
# assignment so pg_dump picks it up via libpq's URI handling.
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

if [ -z "${DATABASE_URL:-}" ]; then
  echo "ERROR: DATABASE_URL is not set in $ENV_FILE" >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"

FILENAME="tayaway-$(date +%Y%m%d-%H%M%S).sql.gz.enc"

# Dump → compress → encrypt in a single pipeline (no plaintext touches disk)
pg_dump "$DATABASE_URL" \
  | gzip \
  | openssl enc -aes-256-cbc -salt -pbkdf2 -pass "file:$KEY_FILE" \
  > "$BACKUP_DIR/$FILENAME"

SIZE=$(du -h "$BACKUP_DIR/$FILENAME" | cut -f1)
echo "$(date -Iseconds) Backup complete: $FILENAME ($SIZE)"

# Delete backups older than retention period
find "$BACKUP_DIR" -name "tayaway-*.sql.gz.enc" -mtime "+$RETENTION_DAYS" -delete
REMAINING=$(find "$BACKUP_DIR" -name "tayaway-*.sql.gz.enc" | wc -l)
echo "$(date -Iseconds) Retained $REMAINING backups (${RETENTION_DAYS}-day window)"
