#!/bin/bash
# InstaBox keepalive — keeps the machine always on (free plan).
# Run from cron every 29 min.  Free-plan limits it beats:
#  - 30-min idle pause      -> exec ping every 29 min keeps it awake
#  - 480-min max run        -> suspend + resume at 420 min = fresh run,
#     NO cooldown (hitting the 480-min limit instead triggers escalating
#     cooldowns: 5-20 -> 60-75 -> 120-135 min)
#  - paused  : resume        stopped : start        cooldown : wait
#
# Secrets are read from files, never hardcoded:
#   ~/.instabox_api_key          -> InstaBox API key (X-API-Key)
#   ~/.redis_keepalive_password  -> password for the Redis Cloud keepalive
#                                   login account (chmod 600)

set -u
KEY=$(cat "$HOME/.instabox_api_key")
ID="REPLACE_WITH_MACHINE_ID"          # e.g. m_xxxxxxxx
API="https://api.instabox.sh/v1"
LOG="$HOME/.instabox_keepalive.log"
TS=$(date '+%F %T')

get() { curl -s --max-time 25 "$API/machines/$ID" -H "X-API-Key: $KEY"; }

info=$(get) || { echo "$TS fetch failed" >> "$LOG"; exit 1; }
read -r state elapsed cooldown <<<"$(printf '%s' "$info" | python3 -c '
import sys, json, datetime
try:
    m = json.load(sys.stdin)
    st = m.get("state", "?")
    rs = m.get("runStartedAt")
    el = -1
    if rs:
        try:
            el = int((datetime.datetime.now(datetime.timezone.utc)
                      - datetime.datetime.fromisoformat(rs.replace("Z", "+00:00"))
                      ).total_seconds() // 60)
        except Exception:
            pass
    cd = m.get("cooldownUntil") or "-"
    print(st, el, cd)
except Exception:
    print("? -1 -")')"

if [ -n "$cooldown" ] && [ "$cooldown" != "-" ] && [ "$cooldown" != "None" ]; then
  echo "$TS in cooldown until $cooldown - waiting" >> "$LOG"; exit 0
fi

case "$state" in
  running)
    if [ "$elapsed" -ge 420 ] 2>/dev/null; then
      curl -s --max-time 25 -X POST "$API/machines/$ID/suspend" \
        -H "X-API-Key: $KEY" -H "Idempotency-Key: $(uuidgen)" \
        -H 'Content-Type: application/json' -d '{}' >/dev/null
      for i in $(seq 1 30); do
        sleep 2
        s=$(get | python3 -c 'import sys,json; m=json.load(sys.stdin)
print(m["state"], m.get("storage",{}).get("synced"))' 2>/dev/null)
        [ "$s" = "paused True" ] && break
      done
      curl -s --max-time 25 -X POST "$API/machines/$ID/resume" \
        -H "X-API-Key: $KEY" -H "Idempotency-Key: $(uuidgen)" \
        -H 'Content-Type: application/json' -d '{}' >/dev/null
      echo "$TS fresh-run flip (was up ${elapsed}m)" >> "$LOG"
    else
      curl -s --max-time 25 -X POST "$API/machines/$ID/exec" \
        -H "X-API-Key: $KEY" -H 'Content-Type: application/json' \
        -d '{"cmd":"true"}' >/dev/null
      echo "$TS ping (up ${elapsed}m)" >> "$LOG"
    fi
    ;;
  paused)
    curl -s --max-time 25 -X POST "$API/machines/$ID/resume" \
      -H "X-API-Key: $KEY" -H "Idempotency-Key: $(uuidgen)" \
      -H 'Content-Type: application/json' -d '{}' >/dev/null
    echo "$TS resumed (was paused)" >> "$LOG"
    ;;
  stopped)
    curl -s --max-time 25 -X POST "$API/machines/$ID/start" \
      -H "X-API-Key: $KEY" -H "Idempotency-Key: $(uuidgen)" \
      -H 'Content-Type: application/json' -d '{}' >/dev/null
    echo "$TS started (was stopped)" >> "$LOG"
    ;;
  *)
    echo "$TS state=$state elapsed=$elapsed - no action" >> "$LOG"
    ;;
esac

# Redis Cloud keepalive (2026-11-14): a free Redis Cloud DB gets deleted
# after 30 days without activity. Every ~6 h: log in with the dedicated
# account -> PUT /api/location -> the DB gets a fresh write.
# Runs on the LOCAL machine (not inside the VM), so it keeps writing even
# when the InstaBox machine is paused. Requires your own app exposing
# /api/users/_login and /api/location; skip this block if you do not need it.
RL="$HOME/.redis_keepalive_last"
RPASS="$HOME/.redis_keepalive_password"
if [ -s "$RPASS" ] && { [ ! -f "$RL" ] || [ $(( $(date +%s) - $(stat -c %Y "$RL") )) -ge 21600 ]; }; then
  RPID="redis-alive-01"               # dedicated keepalive login account
  PASS=$(cat "$RPASS")
  TOK=$(curl -s --max-time 20 -X POST https://api.allert.my.id/api/users/_login \
    -H 'Content-Type: application/json' \
    -d "{\"id\":\"$RPID\",\"password\":\"$PASS\"}" \
    | python3 -c 'import sys,json; print(json.load(sys.stdin).get("data",{}).get("token",""))' 2>/dev/null)
  if [ -n "$TOK" ]; then
    LAT=$(python3 -c "import time; print(round(-6.209900 + (int(time.time())%1000)*1e-6, 6))")
    code=$(curl -s --max-time 25 -o /dev/null -w '%{http_code}' -X PUT \
      https://api.allert.my.id/api/location \
      -H "Authorization: $TOK" -H 'Content-Type: application/json' \
      -d "{\"latitude\": $LAT, \"longitude\": 106.846900}")
    if [ "$code" = "200" ]; then
      touch "$RL"; echo "$TS redis-keepalive ok" >> "$LOG"
    else
      echo "$TS redis-keepalive PUT failed (http $code)" >> "$LOG"
    fi
  else
    echo "$TS redis-keepalive login FAILED" >> "$LOG"
  fi
fi
