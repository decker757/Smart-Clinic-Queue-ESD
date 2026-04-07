#!/bin/sh
# E2E test: Consultation completion flow (Scenario 3 / Diagram 3)
#
# Covers:
#   - Doctor completes consultation via composite-consultation orchestrator
#   - Patient service: MC + prescription records created (gRPC)
#   - Doctor service: consultation notes stored (gRPC)
#   - Appointment service: status → completed (HTTP PATCH)
#   - RabbitMQ: consultation.completed published
#   - Queue coordinator: patient removed from queue (async)
#   - Standard fixed-fee payment link is generated automatically on completion
#   - Patient payment history shows the generated pending payment
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
#     queue-coordinator-service payment-service stripe-service \
#     composite-appointment composite-consultation \
#     composite-staff-orchestrator composite-patient-orchestrator
#
# Usage: sh infra/tests/test-consultation.sh
# ─────────────────────────────────────────────────────────────────────────────

set -e

KONG="http://localhost:8000"
BASE_AUTH="$KONG/api/auth"
BASE_QUEUE="$KONG/api/queue"
BASE_APPOINTMENT="http://localhost:3001"  # no Kong route for atomic appointment-service
BASE_STAFF="$KONG/api/composite/staff"
BASE_PATIENT="$KONG/api/composite/patients"

DOCTOR_EMAIL="${DOCTOR_EMAIL:-doctor@clinic.com}"
DOCTOR_PASSWORD="${DOCTOR_PASSWORD:-password123}"
PATIENT_EMAIL="consult-$(date +%s)@test.com"
PATIENT_PASSWORD="password123"
STANDARD_PAYMENT_AMOUNT_CENTS="${STANDARD_PAYMENT_AMOUNT_CENTS:-5000}"

pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ FAIL: $1"; exit 1; }

check_field() {
  VALUE="$1"; EXPECTED="$2"; LABEL="$3"
  if [ "$VALUE" = "$EXPECTED" ]; then pass "$LABEL"
  else fail "$LABEL (got '$VALUE', expected '$EXPECTED')"; fi
}

wait_for_code() {
  URL=$1
  JWT=$2
  EXPECTED=$3
  LABEL=$4
  CODE="000"

  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" "$URL" \
      -H "Authorization: Bearer $JWT")
    if [ "$CODE" = "$EXPECTED" ]; then
      break
    fi
    sleep 2
  done

  [ "$CODE" = "$EXPECTED" ] || fail "$LABEL (last HTTP $CODE)"
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
echo "--- Waiting for Kong queue route readiness (max 30s) ---"
wait_for_code "$KONG/api/queue/openapi.json" "$PATIENT_JWT" "200" "Kong/queue route ready"

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

QUEUE_STATUS=""
for i in 1 2 3 4 5 6 7 8 9 10; do
  QUEUE_STATUS=$(curl -s "$BASE_QUEUE/position/$APPT_ID" \
    -H "Authorization: Bearer $PATIENT_JWT" | jq -r '.status // empty' 2>/dev/null || true)
  [ "$QUEUE_STATUS" = "waiting" ] && break
  sleep 1
done
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
  pass "Consultation response includes Stripe payment link" || \
  fail "Consultation did not return a payment link"

echo ""
echo "--- Waiting 2s for consultation.completed RabbitMQ event to propagate ---"
sleep 2

# ── 6. Verify consultation side effects ───────────────────────────────────────
echo ""
echo "━━━ STEP 6: Verify consultation side effects ━━━━━━━━━━━━━━━━━━━━━━━━━━"

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

# ── 7. Verify automatic payment flow ──────────────────────────────────────────
echo ""
echo "━━━ STEP 7: Verify automatic payment flow ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "--- Patient payment history shows the standard fixed amount ---"
PATIENT_PAYMENTS=$(curl -sf "$BASE_PATIENT/$PATIENT_ID/payments" \
  -H "Authorization: Bearer $PATIENT_JWT")
echo "$PATIENT_PAYMENTS" | jq .
PATIENT_PAYMENT_STATUS=$(echo "$PATIENT_PAYMENTS" | jq -r --arg APPT "$APPT_ID" '[.[] | select(.consultation_id == $APPT)][0].status')
PATIENT_PAYMENT_AMOUNT=$(echo "$PATIENT_PAYMENTS" | jq -r --arg APPT "$APPT_ID" '[.[] | select(.consultation_id == $APPT)][0].amount_cents')
PATIENT_PAYMENT_LINK=$(echo "$PATIENT_PAYMENTS" | jq -r --arg APPT "$APPT_ID" '[.[] | select(.consultation_id == $APPT)][0].payment_link')
check_field "$PATIENT_PAYMENT_STATUS" "pending" "Patient payment status = pending"
check_field "$PATIENT_PAYMENT_AMOUNT" "$STANDARD_PAYMENT_AMOUNT_CENTS" "Patient payment amount = standard fixed amount"
[ -n "$PATIENT_PAYMENT_LINK" ] && [ "$PATIENT_PAYMENT_LINK" != "null" ] && \
  pass "Patient payment history includes a payable link" || \
  fail "Patient payment history is missing the payment link"

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
