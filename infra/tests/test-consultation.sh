#!/bin/sh
# ─── E2E test: Consultation Orchestrator (Scenario 3) ────────────────────────
#
# PREREQUISITES:
#   1. Start services:
#        cd infra && docker compose up --build \
#          auth-service appointment-service patient-service doctor-service \
#          queue-coordinator-service composite-appointment composite-consultation \
#          rabbitmq
#
#   2. A doctor account must exist in BetterAuth whose user ID matches a record
#      in the doctors table. Set this up once:
#
#        a) Sign up via frontend or:
#             curl -X POST http://localhost:3000/api/auth/sign-up/email \
#               -H "Content-Type: application/json" \
#               -d '{"email":"doctor@clinic.com","password":"password123","name":"Dr Test"}'
#
#        b) Note the returned user.id (a nanoid like "abc123xyz")
#
#        c) Insert a matching doctor record (replace <user_id> with the nanoid):
#             INSERT INTO doctors.doctors (id, name, specialisation, contact)
#             VALUES ('<user_id>', 'Dr Test', 'General', 'dr@clinic.com');
#
#   3. Export credentials before running:
#        export DOCTOR_EMAIL=doctor@clinic.com
#        export DOCTOR_PASSWORD=password123
#
# Usage: sh infra/tests/test-consultation.sh
# ─────────────────────────────────────────────────────────────────────────────

set -e

BASE_AUTH="http://localhost:3000"
BASE_KONG="http://localhost:8000"
BASE_QUEUE="http://localhost:3002"
BASE_APPOINTMENT="http://localhost:3001"
BASE_DOCTOR="http://localhost:3006"

DOCTOR_EMAIL="${DOCTOR_EMAIL:-doctor@clinic.com}"
DOCTOR_PASSWORD="${DOCTOR_PASSWORD:-password123}"
PATIENT_EMAIL="e2e-consult-$(date +%s)@test.com"
PATIENT_PASSWORD="password123"

# ── Helpers ───────────────────────────────────────────────────────────────────

req() {
  TMPFILE=$(mktemp)
  CODE=$(curl -s -o "$TMPFILE" -w "%{http_code}" "$@")
  jq . "$TMPFILE" 2>/dev/null || cat "$TMPFILE"
  echo "[HTTP $CODE]"
  rm -f "$TMPFILE"
}

pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ FAIL: $1"; exit 1; }

check_code() {
  CODE=$1; EXPECTED=$2; LABEL=$3
  if [ "$CODE" = "$EXPECTED" ]; then
    pass "$LABEL"
  else
    fail "$LABEL (got HTTP $CODE, expected $EXPECTED)"
  fi
}

# ── 1. Doctor sign-in ─────────────────────────────────────────────────────────

echo ""
echo "=== 1. Sign in as doctor ==="
DOCTOR_SIGNIN=$(curl -sf -X POST "$BASE_AUTH/api/auth/sign-in/email" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$DOCTOR_EMAIL\",\"password\":\"$DOCTOR_PASSWORD\"}")
echo "$DOCTOR_SIGNIN" | jq .
DOCTOR_SESSION=$(echo "$DOCTOR_SIGNIN" | jq -r '.token')
DOCTOR_USER_ID=$(echo "$DOCTOR_SIGNIN" | jq -r '.user.id')
[ -z "$DOCTOR_USER_ID" ] || [ "$DOCTOR_USER_ID" = "null" ] && \
  fail "Could not sign in as doctor — check DOCTOR_EMAIL and DOCTOR_PASSWORD"
pass "Signed in (user_id=$DOCTOR_USER_ID)"

echo ""
echo "=== 2. Get doctor JWT ==="
DOCTOR_JWT=$(curl -sf "$BASE_AUTH/api/auth/token" \
  -H "Authorization: Bearer $DOCTOR_SESSION" | jq -r '.token')
[ -z "$DOCTOR_JWT" ] || [ "$DOCTOR_JWT" = "null" ] && fail "Could not get doctor JWT"
pass "JWT acquired"

# ── 2. Patient setup ──────────────────────────────────────────────────────────

echo ""
echo "=== 3. Sign up fresh patient ==="
req -X POST "$BASE_AUTH/api/auth/sign-up/email" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$PATIENT_EMAIL\",\"password\":\"$PATIENT_PASSWORD\",\"name\":\"E2E Patient\"}"

PATIENT_SIGNIN=$(curl -sf -X POST "$BASE_AUTH/api/auth/sign-in/email" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$PATIENT_EMAIL\",\"password\":\"$PATIENT_PASSWORD\"}")
PATIENT_ID=$(echo "$PATIENT_SIGNIN" | jq -r '.user.id')
PATIENT_SESSION=$(echo "$PATIENT_SIGNIN" | jq -r '.token')
PATIENT_JWT=$(curl -sf "$BASE_AUTH/api/auth/token" \
  -H "Authorization: Bearer $PATIENT_SESSION" | jq -r '.token')
pass "Patient created (patient_id=$PATIENT_ID)"

# ── 3. Book appointment ───────────────────────────────────────────────────────

echo ""
echo "=== 4. Book appointment ==="
# Pick a unique 15-min slot: days_ahead cycles 1-6, hour cycles 09-17
DAYS_AHEAD=$(( ($(date +%s) / 900) % 6 + 1 ))
HOUR=$(( 9 + ($(date +%s) / 5400) % 9 ))
TOMORROW=$(date -u -v+${DAYS_AHEAD}d "+%Y-%m-%dT$(printf '%02d' $HOUR):00:00Z" 2>/dev/null || \
           date -u -d "+${DAYS_AHEAD} days" "+%Y-%m-%dT$(printf '%02d' $HOUR):00:00Z")
APPT=$(curl -sf -X POST "$BASE_KONG/api/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $PATIENT_JWT" \
  -d "{\"patient_id\":\"$PATIENT_ID\",\"doctor_id\":\"$DOCTOR_USER_ID\",\"start_time\":\"$TOMORROW\"}")
echo "$APPT" | jq .
APPT_ID=$(echo "$APPT" | jq -r '.id // .appointment_id')
[ -z "$APPT_ID" ] || [ "$APPT_ID" = "null" ] && fail "Booking failed — check composite-appointment logs"
pass "Appointment booked (appt_id=$APPT_ID)"

echo ""
echo "--- Waiting 2s for RabbitMQ to process appointment.booked event... ---"
sleep 2

echo ""
echo "=== 5. Verify queue entry created ==="
Q_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_QUEUE/api/queue/position/$APPT_ID")
check_code "$Q_CODE" "200" "Queue entry exists"

# ── 4. Check-in flow ──────────────────────────────────────────────────────────

echo ""
echo "=== 6. Check in patient ==="
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_QUEUE/api/queue/checkin/$APPT_ID")
check_code "$CODE" "200" "Patient checked in"

echo ""
echo "=== 7. Call next (move to called) ==="
req -X POST "$BASE_QUEUE/api/queue/call-next" \
  -H "Content-Type: application/json" \
  -d "{\"doctor_id\":\"$DOCTOR_USER_ID\"}"

# ── 5. Complete consultation ──────────────────────────────────────────────────

echo ""
echo "=== 8. Complete consultation ==="
TODAY=$(date -u '+%Y-%m-%d')
RESULT=$(curl -sf -X POST "$BASE_KONG/api/composite/consultations/complete" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $DOCTOR_JWT" \
  -d "{
    \"appointment_id\": \"$APPT_ID\",
    \"patient_id\":     \"$PATIENT_ID\",
    \"doctor_id\":      \"$DOCTOR_USER_ID\",
    \"diagnosis\":      \"Common cold\",
    \"consultation_notes\": \"Rest and fluids for 3 days\",
    \"mc_days\":        2,
    \"mc_start_date\":  \"$TODAY\",
    \"prescribed_medication\": \"Paracetamol 500mg\"
  }")
echo "$RESULT" | jq .
STATUS=$(echo "$RESULT" | jq -r '.status')
PAYMENT_LINK=$(echo "$RESULT" | jq -r '.payment_link')
[ "$STATUS" = "completed" ] && pass "Consultation completed" || fail "Expected status=completed, got $STATUS"
[ -n "$PAYMENT_LINK" ] && [ "$PAYMENT_LINK" != "null" ] && \
  pass "Payment link returned: $PAYMENT_LINK" || fail "No payment link returned"

echo ""
echo "--- Waiting 2s for RabbitMQ events to propagate... ---"
sleep 2

# ── 6. Verify side effects ────────────────────────────────────────────────────

echo ""
echo "=== 9. Verify appointment status = completed ==="
APPT_STATUS=$(curl -sf "$BASE_APPOINTMENT/appointments/$APPT_ID" \
  -H "Authorization: Bearer $DOCTOR_JWT" | jq -r '.status')
[ "$APPT_STATUS" = "completed" ] && pass "Appointment status = completed" || \
  fail "Appointment status = $APPT_STATUS"

echo ""
echo "=== 10. Verify queue entry removed (expect 404) ==="
Q_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_QUEUE/api/queue/position/$APPT_ID")
check_code "$Q_CODE" "404" "Queue entry removed"

echo ""
echo "=== 11. Verify consultation notes on doctor-service ==="
NOTES_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  "$BASE_DOCTOR/api/doctors/consultations/$PATIENT_ID" \
  -H "Authorization: Bearer $DOCTOR_JWT")
check_code "$NOTES_CODE" "200" "Consultation notes retrievable"
NOTES_APPT=$(curl -sf "$BASE_DOCTOR/api/doctors/consultations/$PATIENT_ID" \
  -H "Authorization: Bearer $DOCTOR_JWT" | jq -r '.[0].appointment_id')
[ "$NOTES_APPT" = "$APPT_ID" ] && pass "Consultation notes linked to correct appointment" || \
  fail "Notes appointment_id mismatch (got $NOTES_APPT)"

echo ""
echo "=== All consultation E2E tests passed! ==="
