#!/usr/bin/env bash
#
# OnFailure handler: post the failed unit's name to ntfy.sh so a crash-looping
# db/web/edge/migrate (or a failed backup / restore-drill) actually pages
# someone instead of giving up silently after StartLimitBurst. Wired up as
# `OnFailure=notify@%n.service` on the long-running units; notify@.service
# passes the failed unit name as $1.
#
# The topic is an unguessable string in the sops production yaml, decrypted
# on demand with the host age key. Failures are rare, so a sops decrypt per
# alert is irrelevant — and it keeps the topic off disk in cleartext (unlike
# /run/tayaway/db.env, which only exists because postgres needs an
# EnvironmentFile). Degrades quietly: no key / no topic / no network just
# means no alert, never a cascading failure of the failure handler itself.
set -euo pipefail

unit="${1:-unknown}"
ENV_YAML=/etc/tayaway/env/.env.production.yaml
AGE=/etc/tayaway/age.key

topic=$(SOPS_AGE_KEY_FILE="$AGE" sops decrypt --extract '["NTFY_TOPIC"]' "$ENV_YAML" 2>/dev/null || true)
if [ -z "$topic" ]; then
  echo "tayaway-notify: NTFY_TOPIC unavailable — cannot alert for '$unit'" >&2
  exit 0
fi

host=$(hostname)
# --fail so an ntfy 5xx/429 is treated as an error rather than swallowed.
# ntfy.sh's free tier rate-limits (429); curl --retry honors Retry-After and
# retries transient codes (408/429/5xx), so a throttled alert still lands.
# --connect-timeout + --retry-max-time bound the whole thing so a hung or
# hard-down ntfy can't wedge the OnFailure handler for long.
if ! curl -fsS \
  --connect-timeout 10 --retry 3 --retry-delay 3 --retry-max-time 40 \
  -H "Title: tayaway alert ($host)" \
  -H "Priority: high" \
  -H "Tags: rotating_light" \
  -d "$unit failed on $host" \
  "https://ntfy.sh/$topic" >/dev/null; then
  echo "tayaway-notify: POST to ntfy failed for '$unit' (ntfy.sh rate limit?)" >&2
fi
