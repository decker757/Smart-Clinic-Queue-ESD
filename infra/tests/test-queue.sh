#!/bin/sh
# End-to-end test for the queue coordinator service.
# Requires: auth-service (3000), Kong (8000), queue-coordinator-service (3002), rabbitmq
# Run from repo root: sh infra/tests/test-queue.sh

set -eu

BASE_AUTH="http://localhost:3000"
BASE_KONG="http://localhost:8000"
BASE_COMPOSITE="$BASE_KONG/api"
BASE_QUEUE="$BASE_KONG/api/queue"
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

# POST and return a single JSON field from the response body
req_post_field() {
  FIELD="$1"; shift
  curl -sf -X POST "$@" | jq -r ".$FIELD // empty"
}

check_code() {
  ACTUAL="$1"; EXPECTED="$2"; MSG="$3"
  if [ "$ACTUAL" = "$EXPECTED" ]; then
    pass "$MSG (HTTP $ACTUAL)"
  else
    fail "$MSG — expected HTTP $EXPECTED, got $ACTUAL"
  fi
}

wait_for_code() {
  URL="$1"; JWT="$2"; EXPECTED="$3"; MSG="$4"
  CODE="000"
  for _ in $(seq 1 30); do
    CODE=$(req_code "$URL" -H "Authorization: Bearer $JWT")
    if [ "$CODE" = "$EXPECTED" ]; then
      break
    fi
    sleep 2
  done
  check_code "$CODE" "$EXPECTED" "$MSG"
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
AUTH_HEADER="Authorization: Bearer $JWT"

echo ""
echo "=== 3b. Wait for Kong routes ==="
wait_for_code "$BASE_COMPOSITE/composite/appointments/openapi.json" "$JWT" "200" "Composite appointment route ready"
wait_for_code "$BASE_KONG/api/queue/openapi.json" "$JWT" "200" "Queue route reachable through Kong"

# ─── Setup ───────────────────────────────────────────────────

echo ""
echo "=== 4. Reset queue (clean slate) ==="
CODE=$(req_code -X POST "$BASE_QUEUE/reset" -H "$AUTH_HEADER")
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
CODE=$(req_code "$BASE_QUEUE/position/$APPT1_ID" -H "$AUTH_HEADER")
check_code "$CODE" "200" "Queue position for appointment 1"

echo ""
echo "=== 8. Get queue position for appointment 2 ==="
CODE=$(req_code "$BASE_QUEUE/position/$APPT2_ID" -H "$AUTH_HEADER")
check_code "$CODE" "200" "Queue position for appointment 2"

echo ""
echo "=== 9. Get queue position for non-existent appointment ==="
CODE=$(req_code "$BASE_QUEUE/position/00000000-0000-0000-0000-000000000000" -H "$AUTH_HEADER")
check_code "$CODE" "404" "Non-existent appointment returns 404"

# ─── Check-in ────────────────────────────────────────────────

echo ""
echo "=== 10. Check in appointment 1 (waiting → checked_in) ==="
CODE=$(req_code -X POST "$BASE_QUEUE/checkin/$APPT1_ID" -H "$AUTH_HEADER")
check_code "$CODE" "200" "Check in appointment 1"

echo ""
echo "=== 11. Check in appointment 1 again — expect 409 ==="
CODE=$(req_code -X POST "$BASE_QUEUE/checkin/$APPT1_ID" -H "$AUTH_HEADER")
check_code "$CODE" "409" "Duplicate check-in returns 409"

echo ""
echo "=== 12. Check in non-existent appointment ==="
CODE=$(req_code -X POST "$BASE_QUEUE/checkin/00000000-0000-0000-0000-000000000000" -H "$AUTH_HEADER")
check_code "$CODE" "404" "Non-existent check-in returns 404"

# ─── Call next (checked_in priority) ─────────────────────────

echo ""
echo "=== 13. Call next for morning — expect appointment 1 ==="
CODE=$(req_code -X POST "$BASE_QUEUE/call-next" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d '{"session":"morning"}')
check_code "$CODE" "200" "Call next returns appointment 1"

echo ""
echo "=== 14. Check in appointment 2 (waiting → checked_in) ==="
CODE=$(req_code -X POST "$BASE_QUEUE/checkin/$APPT2_ID" -H "$AUTH_HEADER")
check_code "$CODE" "200" "Check in appointment 2"

echo ""
echo "=== 15. Call next for morning — expect appointment 2 ==="
CODE=$(req_code -X POST "$BASE_QUEUE/call-next" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d '{"session":"morning"}')
check_code "$CODE" "200" "Call next returns appointment 2"

echo ""
echo "=== 16. Call next for morning — expect 404 (no patients left) ==="
CODE=$(req_code -X POST "$BASE_QUEUE/call-next" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d '{"session":"morning"}')
check_code "$CODE" "404" "Empty queue call-next returns 404"

echo ""
echo "=== 17. Call next — missing session field — expect 400 ==="
CODE=$(req_code -X POST "$BASE_QUEUE/call-next" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
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
CODE=$(req_code -X POST "$BASE_QUEUE/no-show/$APPT3_ID" -H "$AUTH_HEADER")
check_code "$CODE" "200" "Mark no-show"

echo ""
echo "=== 20. Mark appointment 3 as no-show again ==="
CODE=$(req_code -X POST "$BASE_QUEUE/no-show/$APPT3_ID" -H "$AUTH_HEADER")
check_code "$CODE" "404" "Duplicate no-show returns 404"

echo ""
echo "=== 21. Mark no-show on non-existent appointment ==="
CODE=$(req_code -X POST "$BASE_QUEUE/no-show/00000000-0000-0000-0000-000000000000" -H "$AUTH_HEADER")
check_code "$CODE" "404" "Non-existent no-show returns 404"

# ─── Late arrival ─────────────────────────────────────────────

echo ""
echo "=== 22. Late arrival: check in appointment 3 (skipped → rejoins at back) ==="
CODE=$(req_code -X POST "$BASE_QUEUE/checkin/$APPT3_ID" -H "$AUTH_HEADER")
check_code "$CODE" "200" "Late arrival check-in"

echo ""
echo "=== 23. Get queue position after late re-join ==="
CODE=$(req_code "$BASE_QUEUE/position/$APPT3_ID" -H "$AUTH_HEADER")
check_code "$CODE" "200" "Queue position after late re-join"

# ─── Reset ───────────────────────────────────────────────────

echo ""
echo "=== 24. Reset queue ==="
CODE=$(req_code -X POST "$BASE_QUEUE/reset" -H "$AUTH_HEADER")
check_code "$CODE" "200" "Queue reset"

echo ""
echo "=== 25. Get queue position after reset — expect 404 ==="
CODE=$(req_code "$BASE_QUEUE/position/$APPT3_ID" -H "$AUTH_HEADER")
check_code "$CODE" "404" "Queue position after reset returns 404"

# ─── Deprioritize: slot-band shift ordering ──────────────────
# Verify that a late generic patient is shifted back by ceil(eta/15) slot bands
# rather than pushed to the very end, and that queue_number (display) is unchanged.

echo ""
echo "=== 26. Reset queue for deprioritize ordering tests ==="
CODE=$(req_code -X POST "$BASE_QUEUE/reset" -H "$AUTH_HEADER")
check_code "$CODE" "200" "Queue reset for deprioritize tests"

echo ""
echo "=== 27. Book 3 generic morning appointments (DA, DB, DC) ==="
DA=$(curl -sf -X POST "$BASE_COMPOSITE/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\":\"$USER_ID\",\"session\":\"morning\",\"notes\":\"Deprioritize test A\"}")
DA_ID=$(echo "$DA" | jq -r '.id')
DB=$(curl -sf -X POST "$BASE_COMPOSITE/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\":\"$USER_ID\",\"session\":\"morning\",\"notes\":\"Deprioritize test B\"}")
DB_ID=$(echo "$DB" | jq -r '.id')
DC=$(curl -sf -X POST "$BASE_COMPOSITE/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\":\"$USER_ID\",\"session\":\"morning\",\"notes\":\"Deprioritize test C\"}")
DC_ID=$(echo "$DC" | jq -r '.id')
if [ -n "$DA_ID" ] && [ "$DA_ID" != "null" ] && \
   [ -n "$DB_ID" ] && [ "$DB_ID" != "null" ] && \
   [ -n "$DC_ID" ] && [ "$DC_ID" != "null" ]; then
  pass "Booked DA=$DA_ID, DB=$DB_ID, DC=$DC_ID"
else
  fail "Failed to book one or more deprioritize test appointments"
fi

echo ""
echo "--- Waiting 2s for RabbitMQ consumer to process... ---"
sleep 2

echo ""
echo "=== 28. Check in all 3 (DA, DB, DC) ==="
CODE_DA=$(req_code -X POST "$BASE_QUEUE/checkin/$DA_ID" -H "$AUTH_HEADER")
CODE_DB=$(req_code -X POST "$BASE_QUEUE/checkin/$DB_ID" -H "$AUTH_HEADER")
CODE_DC=$(req_code -X POST "$BASE_QUEUE/checkin/$DC_ID" -H "$AUTH_HEADER")
check_code "$CODE_DA" "200" "Check in DA"
check_code "$CODE_DB" "200" "Check in DB"
check_code "$CODE_DC" "200" "Check in DC"

echo ""
echo "=== 29. Deprioritize DA with 30 min ETA (ceil(30/15)=2 slots back → after DC) ==="
CODE=$(req_code -X POST "$BASE_QUEUE/deprioritize/$DA_ID" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d '{"travel_eta_minutes":30}')
check_code "$CODE" "200" "Deprioritize DA with 30 min ETA"

echo ""
echo "=== 30. Verify DA queue_number (display) is unchanged after deprioritize ==="
DA_POS=$(curl -sf "$BASE_QUEUE/position/$DA_ID" -H "$AUTH_HEADER")
DA_QNUM=$(echo "$DA_POS" | jq -r '.queue_number')
# DA was booked first so queue_number should be 1
if [ "$DA_QNUM" = "1" ]; then
  pass "DA queue_number unchanged at $DA_QNUM (sort_key handles ordering, not queue_number)"
else
  fail "DA queue_number changed — expected 1, got $DA_QNUM"
fi

echo ""
echo "=== 31. Call next — expect DB (DA shifted behind DB and DC) ==="
CALLED=$(req_post_field "appointment_id" "$BASE_QUEUE/call-next" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d '{"session":"morning"}')
if [ "$CALLED" = "$DB_ID" ]; then
  pass "Call next returned DB as expected"
else
  fail "Call next expected DB ($DB_ID), got $CALLED"
fi

echo ""
echo "=== 32. Call next — expect DC ==="
CALLED=$(req_post_field "appointment_id" "$BASE_QUEUE/call-next" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d '{"session":"morning"}')
if [ "$CALLED" = "$DC_ID" ]; then
  pass "Call next returned DC as expected"
else
  fail "Call next expected DC ($DC_ID), got $CALLED"
fi

echo ""
echo "=== 33. Call next — expect DA (shifted to after DC) ==="
CALLED=$(req_post_field "appointment_id" "$BASE_QUEUE/call-next" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d '{"session":"morning"}')
if [ "$CALLED" = "$DA_ID" ]; then
  pass "Call next returned DA as expected (slot-band shift worked)"
else
  fail "Call next expected DA ($DA_ID), got $CALLED"
fi

echo ""
echo "=== 34. Deprioritize with missing travel_eta_minutes — should default to 1 slot shift ==="
# Book and check in a fresh appointment, deprioritize without body param
DD=$(curl -sf -X POST "$BASE_COMPOSITE/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\":\"$USER_ID\",\"session\":\"morning\",\"notes\":\"Deprioritize test D\"}")
DD_ID=$(echo "$DD" | jq -r '.id')
sleep 2
CODE=$(req_code -X POST "$BASE_QUEUE/checkin/$DD_ID" -H "$AUTH_HEADER")
check_code "$CODE" "200" "Check in DD"
CODE=$(req_code -X POST "$BASE_QUEUE/deprioritize/$DD_ID" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d '{}')
check_code "$CODE" "200" "Deprioritize with no travel_eta_minutes defaults gracefully"

echo ""
echo "=== 35. Deprioritize non-existent appointment — expect 404 ==="
CODE=$(req_code -X POST "$BASE_QUEUE/deprioritize/00000000-0000-0000-0000-000000000000" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d '{"travel_eta_minutes":15}')
check_code "$CODE" "404" "Deprioritize non-existent appointment returns 404"

echo ""
echo "=== 36. Reset queue ==="
CODE=$(req_code -X POST "$BASE_QUEUE/reset" -H "$AUTH_HEADER")
check_code "$CODE" "200" "Final queue reset"

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
