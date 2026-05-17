#!/usr/bin/env bash
#
# Download the latest DB-IP Lite city database and atomically replace
# $DATA_DIR/dbip-city-lite.mmdb. Designed as a podman `Type=oneshot` —
# exits zero on success so the unit goes inactive (success) and the timer
# fires it again next month.
#
# Atomicity: the download lands at <target>.tmp inside the volume, gets
# a magic-byte sanity check, then is renamed over the target. rename(2)
# on the same filesystem is atomic, so a reader that opened the old file
# keeps reading it and a reader opening fresh sees the new file. No
# partially-written file is ever visible.

set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
MONTH="${MONTH:-$(date -u +%Y-%m)}"
URL="https://download.db-ip.com/free/dbip-city-lite-${MONTH}.mmdb.gz"
TARGET="${DATA_DIR}/dbip-city-lite.mmdb"
TMP="${TARGET}.tmp"

mkdir -p "$DATA_DIR"

echo "[geoip-load] downloading ${URL}"
curl --fail --silent --show-error --location --retry 3 --retry-delay 5 \
  "$URL" | gunzip -c > "$TMP"

# Sanity-check the size. A real DB-IP city-lite mmdb is ~120 MB after
# decompression; an HTML error page or a truncated download is orders of
# magnitude smaller. 10 MB is a comfortable lower bound that still catches
# bad responses without coupling to the exact size of a given month's
# release.
MIN_BYTES=$((10 * 1024 * 1024))
SIZE=$(stat -c '%s' "$TMP")
if [ "$SIZE" -lt "$MIN_BYTES" ]; then
  echo "[geoip-load] downloaded file is only ${SIZE} bytes — refusing to install" >&2
  rm -f "$TMP"
  exit 1
fi

mv -f "$TMP" "$TARGET"
echo "[geoip-load] installed $(stat -c '%s' "$TARGET") bytes at ${TARGET} (release ${MONTH})"
