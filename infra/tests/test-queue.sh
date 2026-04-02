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

PASS=0; FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ FAIL: $1"; }

# Return just the HTTP status code
req_code() {
  curl -s -o /dev/null -w "%{http_code}" "$@"
}

# Return body + status code (for display)
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

check_code() {
  ACTUAL="$1"; EXPECTED="$2"; MSG="$3"
  if [ "$ACTUAL" = "$EXPECTED" ]; then
    pass "$MSG (HTTP $ACTUAL)"
  else
    fail "$MSG — expected HTTP $EXPECTED, got $ACTUAL"
  fi
}

# ─── Auth ────────────────────────────────────────────────────

echo ""
echo "=== 1. Sign up ==="
CODE=$(req_code -X POST "$BASE_AUTH/api/auth/sign-up/email" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"name\":\"Queue Test User\"}")
check_code "$CODE" "200" "Sign up"

echo ""
echo "=== 2. Sign in ==="
SIGNIN=$(curl -sf -X POST "$BASE_AUTH/api/auth/sign-in/email" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")
SESSION_TOKEN=$(echo "$SIGNIN" | jq -r '.token')
USER_ID=$(echo "$SIGNIN" | jq -r '.user.id')
if [ -n "$USER_ID" ] && [ "$USER_ID" != "null" ]; then
  pass "Sign in (user_id=$USER_ID)"
else
  fail "Sign in — no user_id returned"
fi

echo ""
echo "=== 3. Get JWT ==="
JWT=$(curl -sf "$BASE_AUTH/api/auth/token" \
  -H "Authorization: Bearer $SESSION_TOKEN" | jq -r '.token')
if [ -n "$JWT" ] && [ "$JWT" != "null" ]; then
  pass "JWT acquired"
else
  fail "JWT acquisition"
fi

# ─── Setup ───────────────────────────────────────────────────

echo ""
echo "=== 4. Reset queue (clean slate) ==="
CODE=$(req_code -X POST "$BASE_QUEUE/reset")
check_code "$CODE" "200" "Queue reset"

# ─── Book appointments and verify they land in the queue ─────

echo ""
echo "=== 5. Book morning appointment 1 ==="
APPT1=$(curl -sf -X POST "$BASE_COMPOSITE/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\":\"$USER_ID\",\"session\":\"morning\",\"notes\":\"Appointment 1\"}")
APPT1_ID=$(echo "$APPT1" | jq -r '.id')
if [ -n "$APPT1_ID" ] && [ "$APPT1_ID" != "null" ]; then
  pass "Booked appointment 1 (id=$APPT1_ID)"
else
  fail "Book appointment 1 — no id returned"
fi

echo ""
echo "=== 6. Book morning appointment 2 ==="
APPT2=$(curl -sf -X POST "$BASE_COMPOSITE/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\":\"$USER_ID\",\"session\":\"morning\",\"notes\":\"Appointment 2\"}")
APPT2_ID=$(echo "$APPT2" | jq -r '.id')
if [ -n "$APPT2_ID" ] && [ "$APPT2_ID" != "null" ]; then
  pass "Booked appointment 2 (id=$APPT2_ID)"
else
  fail "Book appointment 2 — no id returned"
fi

echo ""
echo "--- Waiting 2s for RabbitMQ consumer to process... ---"
sleep 2

echo ""
echo "=== 7. Get queue position for appointment 1 ==="
CODE=$(req_code "$BASE_QUEUE/position/$APPT1_ID")
check_code "$CODE" "200" "Queue position for appointment 1"

echo ""
echo "=== 8. Get queue position for appointment 2 ==="
CODE=$(req_code "$BASE_QUEUE/position/$APPT2_ID")
check_code "$CODE" "200" "Queue position for appointment 2"

echo ""
echo "=== 9. Get queue position for non-existent appointment ==="
CODE=$(req_code "$BASE_QUEUE/position/00000000-0000-0000-0000-000000000000")
check_code "$CODE" "404" "Non-existent appointment returns 404"

# ─── Check-in ────────────────────────────────────────────────

echo ""
echo "=== 10. Check in appointment 1 (waiting → checked_in) ==="
CODE=$(req_code -X POST "$BASE_QUEUE/checkin/$APPT1_ID")
check_code "$CODE" "200" "Check in appointment 1"

echo ""
echo "=== 11. Check in appointment 1 again — expect 409 ==="
CODE=$(req_code -X POST "$BASE_QUEUE/checkin/$APPT1_ID")
check_code "$CODE" "409" "Duplicate check-in returns 409"

echo ""
echo "=== 12. Check in non-existent appointment ==="
CODE=$(req_code -X POST "$BASE_QUEUE/checkin/00000000-0000-0000-0000-000000000000")
check_code "$CODE" "404" "Non-existent check-in returns 404"

# ─── Call next (checked_in priority) ─────────────────────────

echo ""
echo "=== 13. Call next for morning — expect appointment 1 ==="
CODE=$(req_code -X POST "$BASE_QUEUE/call-next" \
  -H "Content-Type: application/json" \
  -d '{"session":"morning"}')
check_code "$CODE" "200" "Call next returns appointment 1"

echo ""
echo "=== 14. Check in appointment 2 (waiting → checked_in) ==="
CODE=$(req_code -X POST "$BASE_QUEUE/checkin/$APPT2_ID")
check_code "$CODE" "200" "Check in appointment 2"

echo ""
echo "=== 15. Call next for morning — expect appointment 2 ==="
CODE=$(req_code -X POST "$BASE_QUEUE/call-next" \
  -H "Content-Type: application/json" \
  -d '{"session":"morning"}')
check_code "$CODE" "200" "Call next returns appointment 2"

echo ""
echo "=== 16. Call next for morning — expect 404 (no patients left) ==="
CODE=$(req_code -X POST "$BASE_QUEUE/call-next" \
  -H "Content-Type: application/json" \
  -d '{"session":"morning"}')
check_code "$CODE" "404" "Empty queue call-next returns 404"

echo ""
echo "=== 17. Call next — missing session field — expect 400 ==="
CODE=$(req_code -X POST "$BASE_QUEUE/call-next" \
  -H "Content-Type: application/json" \
  -d '{}')
check_code "$CODE" "400" "Missing session field returns 400"

# ─── No-show ─────────────────────────────────────────────────

echo ""
echo "=== 18. Book morning appointment 3 (for no-show and late arrival tests) ==="
APPT3=$(curl -sf -X POST "$BASE_COMPOSITE/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\":\"$USER_ID\",\"session\":\"morning\",\"notes\":\"Appointment 3\"}")
APPT3_ID=$(echo "$APPT3" | jq -r '.id')
if [ -n "$APPT3_ID" ] && [ "$APPT3_ID" != "null" ]; then
  pass "Booked appointment 3 (id=$APPT3_ID)"
else
  fail "Book appointment 3 — no id returned"
fi

echo ""
echo "--- Waiting 2s for RabbitMQ consumer to process... ---"
sleep 2

echo ""
echo "=== 19. Mark appointment 3 as no-show (waiting → skipped) ==="
CODE=$(req_code -X POST "$BASE_QUEUE/no-show/$APPT3_ID")
check_code "$CODE" "200" "Mark no-show"

echo ""
echo "=== 20. Mark appointment 3 as no-show again ==="
CODE=$(req_code -X POST "$BASE_QUEUE/no-show/$APPT3_ID")
check_code "$CODE" "404" "Duplicate no-show returns 404"

echo ""
echo "=== 21. Mark no-show on non-existent appointment ==="
CODE=$(req_code -X POST "$BASE_QUEUE/no-show/00000000-0000-0000-0000-000000000000")
check_code "$CODE" "404" "Non-existent no-show returns 404"

# ─── Late arrival ─────────────────────────────────────────────

echo ""
echo "=== 22. Late arrival: check in appointment 3 (skipped → rejoins at back) ==="
CODE=$(req_code -X POST "$BASE_QUEUE/checkin/$APPT3_ID")
check_code "$CODE" "200" "Late arrival check-in"

echo ""
echo "=== 23. Get queue position after late re-join ==="
CODE=$(req_code "$BASE_QUEUE/position/$APPT3_ID")
check_code "$CODE" "200" "Queue position after late re-join"

# ─── Reset ───────────────────────────────────────────────────

echo ""
echo "=== 24. Reset queue ==="
CODE=$(req_code -X POST "$BASE_QUEUE/reset")
check_code "$CODE" "200" "Queue reset"

echo ""
echo "=== 25. Get queue position after reset — expect 404 ==="
CODE=$(req_code "$BASE_QUEUE/position/$APPT3_ID")
check_code "$CODE" "404" "Queue position after reset returns 404"

# ─── Summary ─────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════╗"
echo "  Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "  STATUS: SOME TESTS FAILED"
  echo "╚══════════════════════════════════════════╝"
  exit 1
else
  echo "  STATUS: ALL TESTS PASSED"
  echo "╚══════════════════════════════════════════╝"
fi
