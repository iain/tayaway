#!/bin/bash
# Daily encrypted PostgreSQL backup for Tayaway.
#
# Setup (one-time, on the server):
#   1. Generate a backup encryption key:
#      openssl rand -base64 32 > /var/www/tayaway/shared/.backup-key
#      chmod 600 /var/www/tayaway/shared/.backup-key
#
#   2. Create the backup directory:
#      mkdir -p /var/www/tayaway/shared/backups
#
#   3. Add cron job (daily at 3am):
#      echo "0 3 * * * /var/www/tayaway/current/config/deploy/backup-db.sh >> /var/log/tayaway-backup.log 2>&1" | crontab -
#
# Restore:
#   openssl enc -d -aes-256-cbc -salt -pbkdf2 \
#     -pass file:/var/www/tayaway/shared/.backup-key \
#     -in /var/www/tayaway/shared/backups/tayaway-20260404-030000.sql.gz.enc \
#     | gunzip | psql tayaway_production
#
set -euo pipefail

DB_NAME="tayaway_production"
BACKUP_DIR="/var/www/tayaway/shared/backups"
KEY_FILE="/var/www/tayaway/shared/.backup-key"
RETENTION_DAYS=30

# Verify key file exists
if [ ! -f "$KEY_FILE" ]; then
  echo "ERROR: Backup key not found at $KEY_FILE" >&2
  echo "Generate one with: openssl rand -base64 32 > $KEY_FILE && chmod 600 $KEY_FILE" >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"

FILENAME="tayaway-$(date +%Y%m%d-%H%M%S).sql.gz.enc"

# Dump → compress → encrypt in a single pipeline (no plaintext touches disk)
pg_dump "$DB_NAME" \
  | gzip \
  | openssl enc -aes-256-cbc -salt -pbkdf2 -pass "file:$KEY_FILE" \
  > "$BACKUP_DIR/$FILENAME"

SIZE=$(du -h "$BACKUP_DIR/$FILENAME" | cut -f1)
echo "$(date -Iseconds) Backup complete: $FILENAME ($SIZE)"

# Delete backups older than retention period
find "$BACKUP_DIR" -name "tayaway-*.sql.gz.enc" -mtime "+$RETENTION_DAYS" -delete
REMAINING=$(find "$BACKUP_DIR" -name "tayaway-*.sql.gz.enc" | wc -l)
echo "$(date -Iseconds) Retained $REMAINING backups (${RETENTION_DAYS}-day window)"
