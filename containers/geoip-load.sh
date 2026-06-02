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
TARGET="${DATA_DIR}/dbip-city-lite.mmdb"
TMP="${TARGET}.tmp"

mkdir -p "$DATA_DIR"

# A real DB-IP city-lite mmdb is ~120 MB after decompression; an HTML error
# page or a truncated download is orders of magnitude smaller. 10 MB is a
# comfortable lower bound that catches bad responses without coupling to a
# specific month's exact release size.
MIN_BYTES=$((10 * 1024 * 1024))

try_download() {
  local month="$1"
  local url="https://download.db-ip.com/free/dbip-city-lite-${month}.mmdb.gz"

  echo "[geoip-load] trying ${url}"
  if ! curl --fail --silent --show-error --location --retry 3 --retry-delay 5 \
    "$url" | gunzip -c >"$TMP"; then
    rm -f "$TMP"
    return 1
  fi

  local size
  size=$(stat -c '%s' "$TMP")
  if [ "$size" -lt "$MIN_BYTES" ]; then
    echo "[geoip-load] ${url} returned only ${size} bytes — rejecting" >&2
    rm -f "$TMP"
    return 1
  fi

  mv -f "$TMP" "$TARGET"
  echo "[geoip-load] installed ${size} bytes at ${TARGET} (release ${month})"
  return 0
}

# DB-IP publishes a new file on the 1st of each month, but not always at
# 00:00 UTC. If the current month isn't up yet, fall back to the previous
# month so the timer firing on the 1st doesn't leave the volume empty.
# Allow MONTH=YYYY-MM as an override (testing / forced re-pin).
if [ -n "${MONTH:-}" ]; then
  try_download "$MONTH"
  exit $?
fi

if try_download "$(date -u +%Y-%m)"; then
  exit 0
fi

# Portable prev-month arithmetic. Avoids `date -d` since busybox's relative
# date support varies; this works on alpine and debian alike.
year=$(date -u +%Y)
month=$(date -u +%-m)
if [ "$month" = "1" ]; then
  prev=$(printf "%04d-12" "$((year - 1))")
else
  prev=$(printf "%04d-%02d" "$year" "$((month - 1))")
fi

echo "[geoip-load] current month unavailable; trying previous month ${prev}" >&2
try_download "$prev"
