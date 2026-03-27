#!/bin/sh
# E2E test: Consultation completion flow (Scenario 3 / Diagram 3)
#
# Covers:
#   - Doctor completes consultation via composite-consultation orchestrator
#   - Patient service: MC + prescription records created (gRPC)
#   - Doctor service: consultation notes stored (gRPC)
#   - Appointment service: status → completed (HTTP PATCH)
#   - Stripe service: checkout session created, payment link returned (gRPC)
#   - RabbitMQ: consultation.completed published
#   - Queue coordinator: patient removed from queue (async)
#
# ── PREREQUISITE: Doctor account ─────────────────────────────────────────────
# A doctor must exist in BetterAuth AND in the doctors table.
# Run once to set it up:
#
#   1. Sign up:
#        curl -X POST http://localhost:8000/api/auth/sign-up/email \
#          -H "Content-Type: application/json" \
#          -d '{"email":"doctor@clinic.com","password":"password123","name":"Dr Test"}'
#
#   2. Note the returned user.id (nanoid, e.g. "abc123xyz")
#
#   3. Insert into doctors table (replace <user_id>):
#        docker exec infra-app-db-1 psql -U app -d clinic -c \
#          "INSERT INTO doctors (id, name, specialisation, contact) \
#           VALUES ('<user_id>', 'Dr Test', 'General', 'dr@clinic.com') \
#           ON CONFLICT DO NOTHING;"
#
# Then export before running:
#   export DOCTOR_EMAIL=doctor@clinic.com
#   export DOCTOR_PASSWORD=password123
#
# ── Required services ─────────────────────────────────────────────────────────
#   cd infra && docker compose up -d \
#     kong auth-service app-db rabbitmq \
#     appointment-service patient-service doctor-service \
#     queue-coordinator-service stripe-service \
#     composite-appointment composite-consultation
#
# Usage: sh infra/tests/test-consultation.sh
# ─────────────────────────────────────────────────────────────────────────────

set -e

KONG="http://localhost:8000"
BASE_AUTH="$KONG/api/auth"
BASE_QUEUE="$KONG/api/queue"
BASE_APPOINTMENT="http://localhost:3001"  # no Kong route for atomic appointment-service

DOCTOR_EMAIL="${DOCTOR_EMAIL:-doctor@clinic.com}"
DOCTOR_PASSWORD="${DOCTOR_PASSWORD:-password123}"
PATIENT_EMAIL="consult-$(date +%s)@test.com"
PATIENT_PASSWORD="password123"

pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ FAIL: $1"; exit 1; }

check_field() {
  VALUE="$1"; EXPECTED="$2"; LABEL="$3"
  if [ "$VALUE" = "$EXPECTED" ]; then pass "$LABEL"
  else fail "$LABEL (got '$VALUE', expected '$EXPECTED')"; fi
}

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║     CONSULTATION E2E TEST (Scenario 3)   ║"
echo "╚══════════════════════════════════════════╝"

# ── 1. Doctor auth ────────────────────────────────────────────────────────────
echo ""
echo "━━━ STEP 1: Doctor sign-in ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

DOCTOR_SIGNIN=$(curl -sf -X POST "$BASE_AUTH/sign-in/email" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$DOCTOR_EMAIL\",\"password\":\"$DOCTOR_PASSWORD\"}")
echo "$DOCTOR_SIGNIN" | jq .
DOCTOR_SESSION=$(echo "$DOCTOR_SIGNIN" | jq -r '.token')
DOCTOR_USER_ID=$(echo "$DOCTOR_SIGNIN" | jq -r '.user.id')
[ -z "$DOCTOR_USER_ID" ] || [ "$DOCTOR_USER_ID" = "null" ] && \
  fail "Doctor sign-in failed — run the prerequisite setup steps above"
pass "Doctor signed in (user_id=$DOCTOR_USER_ID)"

DOCTOR_JWT=$(curl -sf "$BASE_AUTH/token" \
  -H "Authorization: Bearer $DOCTOR_SESSION" | jq -r '.token')
[ -z "$DOCTOR_JWT" ] || [ "$DOCTOR_JWT" = "null" ] && fail "Could not get doctor JWT"
pass "Doctor JWT acquired"

# ── 2. Patient setup ──────────────────────────────────────────────────────────
echo ""
echo "━━━ STEP 2: Patient signup + book appointment ━━━━━━━━━━━━━━━━━━━━━━━━━━"

curl -sf -X POST "$BASE_AUTH/sign-up/email" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$PATIENT_EMAIL\",\"password\":\"$PATIENT_PASSWORD\",\"name\":\"E2E Patient\"}" | jq .

PATIENT_SIGNIN=$(curl -sf -X POST "$BASE_AUTH/sign-in/email" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$PATIENT_EMAIL\",\"password\":\"$PATIENT_PASSWORD\"}")
PATIENT_ID=$(echo "$PATIENT_SIGNIN" | jq -r '.user.id')
PATIENT_SESSION=$(echo "$PATIENT_SIGNIN" | jq -r '.token')
PATIENT_JWT=$(curl -sf "$BASE_AUTH/token" \
  -H "Authorization: Bearer $PATIENT_SESSION" | jq -r '.token')
pass "Patient created (patient_id=$PATIENT_ID)"

echo ""
echo "--- Book appointment with doctor $DOCTOR_USER_ID ---"
APPT=$(curl -sf -X POST "$KONG/api/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $PATIENT_JWT" \
  -d "{\"patient_id\":\"$PATIENT_ID\",\"session\":\"morning\",\"notes\":\"E2E consultation test\"}")
echo "$APPT" | jq .
APPT_ID=$(echo "$APPT" | jq -r '.id')
[ -z "$APPT_ID" ] || [ "$APPT_ID" = "null" ] && fail "Appointment booking failed"
pass "Appointment booked (appt_id=$APPT_ID)"

echo ""
echo "--- Waiting 2s for appointment.booked event to create queue entry ---"
sleep 2

# ── 3. Verify queue entry ─────────────────────────────────────────────────────
echo ""
echo "━━━ STEP 3: Verify queue entry ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

QUEUE_STATUS=$(curl -sf "$BASE_QUEUE/position/$APPT_ID" \
  -H "Authorization: Bearer $PATIENT_JWT" | jq -r '.status')
check_field "$QUEUE_STATUS" "waiting" "Queue entry status = waiting"

# ── 4. Check in patient (direct queue call — check-in orchestrator tested separately) ─
echo ""
echo "━━━ STEP 4: Check in patient ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

curl -sf -X POST "$BASE_QUEUE/checkin/$APPT_ID" \
  -H "Authorization: Bearer $PATIENT_JWT" | jq .
QUEUE_STATUS=$(curl -sf "$BASE_QUEUE/position/$APPT_ID" \
  -H "Authorization: Bearer $PATIENT_JWT" | jq -r '.status')
check_field "$QUEUE_STATUS" "checked_in" "Queue entry status = checked_in"

# ── 5. Complete consultation ──────────────────────────────────────────────────
echo ""
echo "━━━ STEP 5: Doctor completes consultation ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

TODAY=$(date -u '+%Y-%m-%d')
RESULT=$(curl -sf -X POST "$KONG/api/composite/consultations/complete" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $DOCTOR_JWT" \
  -d "{
    \"appointment_id\":      \"$APPT_ID\",
    \"patient_id\":          \"$PATIENT_ID\",
    \"doctor_id\":           \"$DOCTOR_USER_ID\",
    \"diagnosis\":           \"Common cold\",
    \"consultation_notes\":  \"Rest and fluids for 3 days\",
    \"mc_days\":             2,
    \"mc_start_date\":       \"$TODAY\",
    \"prescribed_medication\": \"Paracetamol 500mg\"
  }")
echo "$RESULT" | jq .

STATUS=$(echo "$RESULT" | jq -r '.status')
PAYMENT_LINK=$(echo "$RESULT" | jq -r '.payment_link')
check_field "$STATUS" "completed" "Consultation status = completed"
[ -n "$PAYMENT_LINK" ] && [ "$PAYMENT_LINK" != "null" ] && \
  pass "Stripe payment link returned" || fail "No payment link (check STRIPE_API_KEY in stripe-service.env)"

echo ""
echo "--- Waiting 2s for consultation.completed RabbitMQ event to propagate ---"
sleep 2

# ── 6. Verify side effects ────────────────────────────────────────────────────
echo ""
echo "━━━ STEP 6: Verify side effects ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "--- Appointment status (via appointment-service) ---"
APPT_STATUS=$(curl -sf "$BASE_APPOINTMENT/appointments/$APPT_ID" \
  -H "Authorization: Bearer $DOCTOR_JWT" | jq -r '.status')
check_field "$APPT_STATUS" "completed" "Appointment status = completed"

echo ""
echo "--- Queue entry gone from active queue after consultation.completed ---"
# getQueuePosition filters out 'done' entries → returns 404. Retry up to 5s.
Q_CODE="200"
for i in 1 2 3 4 5; do
  Q_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_QUEUE/position/$APPT_ID" \
    -H "Authorization: Bearer $PATIENT_JWT")
  [ "$Q_CODE" = "404" ] && break
  sleep 1
done
[ "$Q_CODE" = "404" ] && pass "Patient no longer in active queue (404)" || \
  fail "Expected 404 after consultation completed, got HTTP $Q_CODE"

echo ""
echo "--- Notification service logs (should show consultation.completed SMS) ---"
docker logs infra-notification-service-1 --tail 10 2>/dev/null || \
  echo "(run via docker compose to see logs)"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║        ALL CONSULTATION TESTS PASSED     ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "Payment link: $PAYMENT_LINK"
echo ""
echo "Check RabbitMQ event delivery:"
echo "  docker logs infra-queue-coordinator-service-1 --tail 20"
echo "  docker logs infra-notification-service-1 --tail 20"
echo "  docker logs stripe-service --tail 10"
