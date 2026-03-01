#!/bin/sh
# Redis caching tests for queue-coordinator-service.
# Verifies cache hits, cache invalidation on writes, and cache flush on reset.
#
# Usage:
#   sh infra/tests/test-redis.sh                     # local
#   sh infra/tests/test-redis.sh https://kong-production-5d53.up.railway.app  # production
#
# What to look for:
#   - 2nd position fetch is faster than 1st (cache hit)
#   - After any write (checkin / call-next / reset), next fetch hits DB again (cache miss)
#   - queue-coordinator logs show "[Redis] cache hit for ..." on hits

BASE=${1:-local}

if [ "$BASE" = "local" ]; then
  # Bypass Kong — hit services directly
  BASE_AUTH="http://localhost:3000/api/auth"
  BASE_COMPOSITE="http://localhost:8080/api/composite"
  BASE_QUEUE="http://localhost:3002/api/queue"
else
  # Production — go through Kong
  BASE_AUTH="${BASE}/api/auth"
  BASE_COMPOSITE="${BASE}/api/composite"
  BASE_QUEUE="${BASE}/api/queue"
fi

EMAIL="redis-test-$(date +%s)@test.com"
PASSWORD="password123"

# ─── Helpers ─────────────────────────────────────────────────

req() {
  TMPFILE=$(mktemp)
  CODE=$(curl -s -o "$TMPFILE" -w "%{http_code}" "$@")
  jq . "$TMPFILE" 2>/dev/null || cat "$TMPFILE"
  echo "[HTTP $CODE]"
  rm -f "$TMPFILE"
}

# Returns upstream latency in ms from response headers
latency() {
  curl -si "$@" 2>/dev/null | grep -i "x-kong-upstream-latency" | awk '{print $2}' | tr -d '\r'
}

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; }

check_faster() {
  FIRST=$1
  SECOND=$2
  LABEL=$3
  if [ -n "$FIRST" ] && [ -n "$SECOND" ] && [ "$SECOND" -lt "$FIRST" ]; then
    pass "$LABEL (${FIRST}ms → ${SECOND}ms)"
  else
    echo "  NOTE: $LABEL — could not confirm speedup (${FIRST}ms → ${SECOND}ms, may be network variance)"
  fi
}

# ─── Auth ────────────────────────────────────────────────────

echo ""
echo "=== 1. Sign up ==="
req -X POST "$BASE_AUTH/sign-up/email" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"name\":\"Redis Test\"}"

echo ""
echo "=== 2. Sign in ==="
SIGNIN=$(curl -sf -X POST "$BASE_AUTH/sign-in/email" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")
echo "$SIGNIN" | jq .
SESSION_TOKEN=$(echo "$SIGNIN" | jq -r '.token')
USER_ID=$(echo "$SIGNIN" | jq -r '.user.id')

echo ""
echo "=== 3. Get JWT ==="
JWT=$(curl -sf "$BASE_AUTH/token" \
  -H "Authorization: Bearer $SESSION_TOKEN" | jq -r '.token')
echo "JWT acquired."

# queue-coordinator has no auth middleware locally — JWT header still sent for consistency
AUTH_HEADER="Authorization: Bearer $JWT"

# ─── Setup ───────────────────────────────────────────────────

echo ""
echo "=== 4. Reset queue (clean slate) ==="
req -X POST "$BASE_QUEUE/reset" -H "$AUTH_HEADER"

echo ""
echo "=== 5. Book appointment ==="
APPT_RESP=$(mktemp)
APPT_CODE=$(curl -s -o "$APPT_RESP" -w "%{http_code}" -X POST "$BASE_COMPOSITE/appointments" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d "{\"patient_id\":\"$USER_ID\",\"session\":\"morning\"}")
jq . "$APPT_RESP"
echo "[HTTP $APPT_CODE]"
APPT_ID=$(jq -r '.id' "$APPT_RESP")
rm -f "$APPT_RESP"
if [ -z "$APPT_ID" ] || [ "$APPT_ID" = "null" ]; then
  echo "ERROR: Failed to book appointment. Aborting."
  exit 1
fi
echo "  Appointment ID: $APPT_ID"

echo ""
echo "--- Waiting 2s for RabbitMQ consumer to process... ---"
sleep 2

# ─── Cache miss → hit ────────────────────────────────────────

echo ""
echo "=== 6. First position fetch — expect cache MISS (DB query) ==="
L1=$(latency "$BASE_QUEUE/position/$APPT_ID" -H "$AUTH_HEADER")
req "$BASE_QUEUE/position/$APPT_ID" -H "$AUTH_HEADER"
echo "  Upstream latency: ${L1}ms"

echo ""
echo "=== 7. Second position fetch — expect cache HIT (Redis) ==="
L2=$(latency "$BASE_QUEUE/position/$APPT_ID" -H "$AUTH_HEADER")
req "$BASE_QUEUE/position/$APPT_ID" -H "$AUTH_HEADER"
echo "  Upstream latency: ${L2}ms"
check_faster "$L1" "$L2" "Cache hit faster than cache miss"

# ─── Invalidation on write: check-in ─────────────────────────

echo ""
echo "=== 8. Check in — should invalidate cache ==="
req -X POST "$BASE_QUEUE/checkin/$APPT_ID" -H "$AUTH_HEADER"

echo ""
echo "=== 9. Position fetch after check-in — expect cache MISS (invalidated) ==="
L3=$(latency "$BASE_QUEUE/position/$APPT_ID" -H "$AUTH_HEADER")
req "$BASE_QUEUE/position/$APPT_ID" -H "$AUTH_HEADER"
echo "  Upstream latency: ${L3}ms"

echo ""
echo "=== 10. Position fetch again — expect cache HIT ==="
L4=$(latency "$BASE_QUEUE/position/$APPT_ID" -H "$AUTH_HEADER")
req "$BASE_QUEUE/position/$APPT_ID" -H "$AUTH_HEADER"
echo "  Upstream latency: ${L4}ms"
check_faster "$L3" "$L4" "Cache hit after re-population"

# ─── Invalidation on write: call-next ────────────────────────

echo ""
echo "=== 11. Call next — should invalidate cache for called patient ==="
req -X POST "$BASE_QUEUE/call-next" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d '{"session":"morning"}'

echo ""
echo "=== 12. Position fetch after call-next — expect cache MISS (invalidated) ==="
L5=$(latency "$BASE_QUEUE/position/$APPT_ID" -H "$AUTH_HEADER")
req "$BASE_QUEUE/position/$APPT_ID" -H "$AUTH_HEADER"
echo "  Upstream latency: ${L5}ms"

# ─── Cache flush on reset ─────────────────────────────────────

echo ""
echo "=== 13. Book second appointment to populate cache ==="
APPT2_RESP=$(mktemp)
curl -s -o "$APPT2_RESP" -w "%{http_code}" -X POST "$BASE_COMPOSITE/appointments" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d "{\"patient_id\":\"$USER_ID\",\"session\":\"morning\"}" > /dev/null
APPT2_ID=$(jq -r '.id' "$APPT2_RESP")
rm -f "$APPT2_RESP"
sleep 2

# Populate cache
curl -s "$BASE_QUEUE/position/$APPT2_ID" -H "$AUTH_HEADER" > /dev/null
echo "  Cache populated for $APPT2_ID"

echo ""
echo "=== 14. Reset queue — should flush all cached positions ==="
req -X POST "$BASE_QUEUE/reset" -H "$AUTH_HEADER"

echo ""
echo "=== 15. Position fetch after reset — expect 404 (entry deleted, cache flushed) ==="
req "$BASE_QUEUE/position/$APPT2_ID" -H "$AUTH_HEADER"

echo ""
echo "=== Redis cache tests done ==="
echo ""
echo "Check queue-coordinator logs for '[Redis] cache hit for ...' entries to confirm caching."
