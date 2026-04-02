#!/bin/sh
# End-to-end test for the queue coordinator service.
# Requires: auth-service (3000), composite-appointment (8080), queue-coordinator-service (3002), rabbitmq
# Run from repo root: sh infra/tests/test-queue.sh

set -e

BASE_AUTH="http://localhost:3000"
BASE_COMPOSITE="http://localhost:8080/api"
BASE_QUEUE="http://localhost:3002/api/queue"
EMAIL="qtest-$(date +%s)@test.com"
PASSWORD="password123"

# curl wrapper: always show body + HTTP status on a new line
req() {
  TMPFILE=$(mktemp)
  CODE=$(curl -s -o "$TMPFILE" -w "%{http_code}" "$@")
  if jq . "$TMPFILE" >/dev/null 2>&1; then
    jq . "$TMPFILE"
  else
    cat "$TMPFILE"
  fi
  echo "[HTTP $CODE]"
  rm -f "$TMPFILE"
}

# ─── Auth ────────────────────────────────────────────────────

echo ""
echo "=== 1. Sign up ==="
req -X POST "$BASE_AUTH/api/auth/sign-up/email" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"name\":\"Queue Test User\"}"

echo ""
echo "=== 2. Sign in ==="
SIGNIN=$(curl -sf -X POST "$BASE_AUTH/api/auth/sign-in/email" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")
echo "$SIGNIN" | jq .
SESSION_TOKEN=$(echo "$SIGNIN" | jq -r '.token')
USER_ID=$(echo "$SIGNIN" | jq -r '.user.id')

echo ""
echo "=== 3. Get JWT ==="
JWT=$(curl -sf "$BASE_AUTH/api/auth/token" \
  -H "Authorization: Bearer $SESSION_TOKEN" | jq -r '.token')
echo "JWT acquired."

# ─── Setup ───────────────────────────────────────────────────

echo ""
echo "=== 4. Reset queue (clean slate) ==="
req -X POST "$BASE_QUEUE/reset"

# ─── Book appointments and verify they land in the queue ─────

echo ""
echo "=== 5. Book morning appointment 1 ==="
APPT1=$(curl -sf -X POST "$BASE_COMPOSITE/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\":\"$USER_ID\",\"session\":\"morning\",\"notes\":\"Appointment 1\"}")
echo "$APPT1" | jq .
APPT1_ID=$(echo "$APPT1" | jq -r '.id')
[ -n "$APPT1_ID" ] && [ "$APPT1_ID" != "null" ]

echo ""
echo "=== 6. Book morning appointment 2 ==="
APPT2=$(curl -sf -X POST "$BASE_COMPOSITE/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\":\"$USER_ID\",\"session\":\"morning\",\"notes\":\"Appointment 2\"}")
echo "$APPT2" | jq .
APPT2_ID=$(echo "$APPT2" | jq -r '.id')
[ -n "$APPT2_ID" ] && [ "$APPT2_ID" != "null" ]

echo ""
echo "--- Waiting 2s for RabbitMQ consumer to process... ---"
sleep 2

echo ""
echo "=== 7. Get queue position for appointment 1 (expect queue_number=1) ==="
req "$BASE_QUEUE/position/$APPT1_ID"

echo ""
echo "=== 8. Get queue position for appointment 2 (expect queue_number=2) ==="
req "$BASE_QUEUE/position/$APPT2_ID"

echo ""
echo "=== 9. Get queue position for non-existent appointment — expect 404 ==="
req "$BASE_QUEUE/position/00000000-0000-0000-0000-000000000000"

# ─── Check-in ────────────────────────────────────────────────

echo ""
echo "=== 10. Check in appointment 1 (waiting → checked_in) ==="
req -X POST "$BASE_QUEUE/checkin/$APPT1_ID"

echo ""
echo "=== 11. Check in appointment 1 again — expect 409 ==="
req -X POST "$BASE_QUEUE/checkin/$APPT1_ID"

echo ""
echo "=== 12. Check in non-existent appointment — expect 404 ==="
req -X POST "$BASE_QUEUE/checkin/00000000-0000-0000-0000-000000000000"

# ─── Call next (checked_in priority) ─────────────────────────

echo ""
echo "=== 13. Call next for morning — expect appointment 1 (checked_in has priority over waiting) ==="
req -X POST "$BASE_QUEUE/call-next" \
  -H "Content-Type: application/json" \
  -d '{"session":"morning"}'

echo ""
echo "=== 14. Check in appointment 2 (waiting → checked_in) ==="
req -X POST "$BASE_QUEUE/checkin/$APPT2_ID"

echo ""
echo "=== 15. Call next for morning — expect appointment 2 ==="
req -X POST "$BASE_QUEUE/call-next" \
  -H "Content-Type: application/json" \
  -d '{"session":"morning"}'

echo ""
echo "=== 16. Call next for morning — expect 404 (no patients left) ==="
req -X POST "$BASE_QUEUE/call-next" \
  -H "Content-Type: application/json" \
  -d '{"session":"morning"}'

echo ""
echo "=== 17. Call next — missing session field — expect 400 ==="
req -X POST "$BASE_QUEUE/call-next" \
  -H "Content-Type: application/json" \
  -d '{}'

# ─── No-show ─────────────────────────────────────────────────

echo ""
echo "=== 18. Book morning appointment 3 (for no-show and late arrival tests) ==="
APPT3=$(curl -sf -X POST "$BASE_COMPOSITE/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\":\"$USER_ID\",\"session\":\"morning\",\"notes\":\"Appointment 3\"}")
echo "$APPT3" | jq .
APPT3_ID=$(echo "$APPT3" | jq -r '.id')
[ -n "$APPT3_ID" ] && [ "$APPT3_ID" != "null" ]

echo ""
echo "--- Waiting 2s for RabbitMQ consumer to process... ---"
sleep 2

echo ""
echo "=== 19. Mark appointment 3 as no-show (waiting → skipped) ==="
req -X POST "$BASE_QUEUE/no-show/$APPT3_ID"

echo ""
echo "=== 20. Mark appointment 3 as no-show again — expect 404 ==="
req -X POST "$BASE_QUEUE/no-show/$APPT3_ID"

echo ""
echo "=== 21. Mark no-show on non-existent appointment — expect 404 ==="
req -X POST "$BASE_QUEUE/no-show/00000000-0000-0000-0000-000000000000"

# ─── Late arrival ─────────────────────────────────────────────

echo ""
echo "=== 22. Late arrival: check in appointment 3 (skipped → rejoins at back with new queue_number) ==="
req -X POST "$BASE_QUEUE/checkin/$APPT3_ID"

echo ""
echo "=== 23. Get queue position after late re-join (queue_number should be > 2) ==="
req "$BASE_QUEUE/position/$APPT3_ID"

# ─── Reset ───────────────────────────────────────────────────

echo ""
echo "=== 24. Reset queue ==="
req -X POST "$BASE_QUEUE/reset"

echo ""
echo "=== 25. Get queue position after reset — expect 404 ==="
req "$BASE_QUEUE/position/$APPT3_ID"

echo ""
echo "=== All queue tests done ==="
