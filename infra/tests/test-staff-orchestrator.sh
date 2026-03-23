#!/bin/sh
# ─── E2E test: Staff Management Orchestrator ─────────────────────────────────
#
# PREREQUISITES:
#   1. Start services:
#        cd infra && docker compose up --build \
#          auth-service appointment-service patient-service doctor-service \
#          queue-coordinator-service composite-appointment \
#          composite-staff-orchestrator rabbitmq kong
#
#   2. A doctor account must exist in BetterAuth whose user ID matches a record
#      in the doctors table. Set up once:
#
#        a) Sign up:
#             curl -X POST http://localhost:3000/api/auth/sign-up/email \
#               -H "Content-Type: application/json" \
#               -d '{"email":"doctor@clinic.com","password":"password123","name":"Dr Test"}'
#
#        b) Note the returned user.id (nanoid e.g. "abc123xyz")
#
#        c) Insert a matching doctor row:
#             INSERT INTO doctors.doctors (id, name, specialisation, contact)
#             VALUES ('<user_id>', 'Dr Test', 'General', 'dr@clinic.com');
#
#        d) Ensure the JWT includes role="doctor".
#           If BetterAuth does not add the role claim automatically, set it
#           in the user's metadata or via a BetterAuth plugin.
#
#   3. Export credentials before running:
#        export DOCTOR_EMAIL=doctor@clinic.com
#        export DOCTOR_PASSWORD=password123
#
# Usage: sh infra/tests/test-staff-orchestrator.sh
# ─────────────────────────────────────────────────────────────────────────────

set -e

BASE_AUTH="http://localhost:3000"
BASE_KONG="http://localhost:8000"
BASE_STAFF="$BASE_KONG/api/composite/staff"

DOCTOR_EMAIL="${DOCTOR_EMAIL:-doctor@clinic.com}"
DOCTOR_PASSWORD="${DOCTOR_PASSWORD:-password123}"
PATIENT_EMAIL="e2e-staff-$(date +%s)@test.com"
PATIENT_PASSWORD="password123"

# ── Helpers ───────────────────────────────────────────────────────────────────

req() {
  TMPFILE=$(mktemp)
  CODE=$(curl -s -o "$TMPFILE" -w "%{http_code}" "$@")
  jq . "$TMPFILE" 2>/dev/null || cat "$TMPFILE"
  echo "[HTTP $CODE]"
  rm -f "$TMPFILE"
}

req_code() {
  curl -s -o /dev/null -w "%{http_code}" "$@"
}

req_json() {
  curl -sf "$@"
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

# ── 1. Auth ───────────────────────────────────────────────────────────────────

echo ""
echo "=== 1. Sign in as doctor ==="
DOCTOR_SIGNIN=$(curl -sf -X POST "$BASE_AUTH/api/auth/sign-in/email" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$DOCTOR_EMAIL\",\"password\":\"$DOCTOR_PASSWORD\"}")
echo "$DOCTOR_SIGNIN" | jq .
DOCTOR_SESSION=$(echo "$DOCTOR_SIGNIN" | jq -r '.token')
DOCTOR_ID=$(echo "$DOCTOR_SIGNIN" | jq -r '.user.id')
[ -z "$DOCTOR_ID" ] || [ "$DOCTOR_ID" = "null" ] && \
  fail "Could not sign in as doctor — check DOCTOR_EMAIL and DOCTOR_PASSWORD"
pass "Signed in (doctor_id=$DOCTOR_ID)"

echo ""
echo "=== 2. Get doctor JWT ==="
DOCTOR_JWT=$(req_json "$BASE_AUTH/api/auth/token" \
  -H "Authorization: Bearer $DOCTOR_SESSION" | jq -r '.token')
[ -z "$DOCTOR_JWT" ] || [ "$DOCTOR_JWT" = "null" ] && fail "Could not get doctor JWT"
pass "JWT acquired"

# ── 2. Doctor endpoints ───────────────────────────────────────────────────────

echo ""
echo "=== 3. List doctors ==="
DOCTORS=$(req_json "$BASE_STAFF/doctors" \
  -H "Authorization: Bearer $DOCTOR_JWT")
echo "$DOCTORS" | jq .
DOCTOR_COUNT=$(echo "$DOCTORS" | jq 'length')
[ "$DOCTOR_COUNT" -ge 1 ] && pass "Listed $DOCTOR_COUNT doctor(s)" || fail "No doctors returned"

echo ""
echo "=== 4. Get doctor by ID ==="
CODE=$(req_code "$BASE_STAFF/doctors/$DOCTOR_ID" \
  -H "Authorization: Bearer $DOCTOR_JWT")
check_code "$CODE" "200" "Get doctor by ID"

echo ""
echo "=== 5. Get doctor slots ==="
SLOTS_RESP=$(req_json "$BASE_STAFF/doctors/$DOCTOR_ID/slots" \
  -H "Authorization: Bearer $DOCTOR_JWT")
echo "$SLOTS_RESP" | jq .
SLOT_ID=$(echo "$SLOTS_RESP" | jq -r '.[0].id // empty')
pass "Got doctor slots"

if [ -n "$SLOT_ID" ] && [ "$SLOT_ID" != "null" ]; then
  echo ""
  echo "=== 6. Update slot status ==="
  CODE=$(req_code -X PATCH "$BASE_STAFF/doctors/slots/$SLOT_ID" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $DOCTOR_JWT" \
    -d '{"status":"unavailable"}')
  check_code "$CODE" "200" "Update slot status to unavailable"

  CODE=$(req_code -X PATCH "$BASE_STAFF/doctors/slots/$SLOT_ID" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $DOCTOR_JWT" \
    -d '{"status":"available"}')
  check_code "$CODE" "200" "Restore slot status to available"
else
  echo "  (skipping slot update — no slots found for doctor)"
fi

# ── 3. Patient setup + viewing ────────────────────────────────────────────────

echo ""
echo "=== 7. Create a test patient ==="
req -X POST "$BASE_AUTH/api/auth/sign-up/email" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$PATIENT_EMAIL\",\"password\":\"$PATIENT_PASSWORD\",\"name\":\"E2E Staff Patient\"}"

PATIENT_SIGNIN=$(curl -sf -X POST "$BASE_AUTH/api/auth/sign-in/email" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$PATIENT_EMAIL\",\"password\":\"$PATIENT_PASSWORD\"}")
PATIENT_ID=$(echo "$PATIENT_SIGNIN" | jq -r '.user.id')
PATIENT_SESSION=$(echo "$PATIENT_SIGNIN" | jq -r '.token')
PATIENT_JWT=$(req_json "$BASE_AUTH/api/auth/token" \
  -H "Authorization: Bearer $PATIENT_SESSION" | jq -r '.token')
pass "Patient created (patient_id=$PATIENT_ID)"

echo ""
echo "=== 7b. Create patient profile in patient-service ==="
CODE=$(req_code -X POST "$BASE_KONG/api/patients" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $PATIENT_JWT" \
  -d '{"phone":"91234567","dob":"2000-01-01","nric":"S1234567A","allergies":[]}')
check_code "$CODE" "201" "Patient profile created in patient-service"

echo ""
echo "=== 8. View patient profile (staff) ==="
CODE=$(req_code "$BASE_STAFF/patients/$PATIENT_ID" \
  -H "Authorization: Bearer $DOCTOR_JWT")
check_code "$CODE" "200" "Staff can view patient profile"

echo ""
echo "=== 9. View patient history (staff) ==="
CODE=$(req_code "$BASE_STAFF/patients/$PATIENT_ID/history" \
  -H "Authorization: Bearer $DOCTOR_JWT")
check_code "$CODE" "200" "Staff can view patient history"

# ── 4. Auth guard check ───────────────────────────────────────────────────────

echo ""
echo "=== 10. Reject unauthenticated request ==="
CODE=$(req_code "$BASE_STAFF/doctors")
check_code "$CODE" "401" "Unauthenticated request rejected by Kong"

echo ""
echo "=== 11. Reject patient JWT on staff route ==="
CODE=$(req_code "$BASE_STAFF/doctors" \
  -H "Authorization: Bearer $PATIENT_JWT")
check_code "$CODE" "403" "Patient JWT rejected (insufficient role)"

# ── 5. Queue management ───────────────────────────────────────────────────────

echo ""
echo "=== 12. Book appointment via composite-appointment ==="
DAYS_AHEAD=$(( ($(date +%s) / 900) % 6 + 1 ))
HOUR=$(( 9 + ($(date +%s) / 5400) % 9 ))
START_TIME=$(date -u -v+${DAYS_AHEAD}d "+%Y-%m-%dT$(printf '%02d' $HOUR):00:00Z" 2>/dev/null || \
             date -u -d "+${DAYS_AHEAD} days" "+%Y-%m-%dT$(printf '%02d' $HOUR):00:00Z")
SESSION=$(date -u -v+${DAYS_AHEAD}d "+%Y-%m-%d" 2>/dev/null || \
          date -u -d "+${DAYS_AHEAD} days" "+%Y-%m-%d")

APPT=$(curl -sf -X POST "$BASE_KONG/api/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $PATIENT_JWT" \
  -d "{\"patient_id\":\"$PATIENT_ID\",\"doctor_id\":\"$DOCTOR_ID\",\"start_time\":\"$START_TIME\"}")
echo "$APPT" | jq .
APPT_ID=$(echo "$APPT" | jq -r '.id // .appointment_id')
[ -z "$APPT_ID" ] || [ "$APPT_ID" = "null" ] && fail "Booking failed — check composite-appointment logs"
pass "Appointment booked (appt_id=$APPT_ID)"

echo ""
echo "--- Waiting 2s for appointment.booked event to be processed... ---"
sleep 2

echo ""
echo "=== 13. Get queue position (staff) ==="
CODE=$(req_code "$BASE_STAFF/queue/$APPT_ID/position" \
  -H "Authorization: Bearer $DOCTOR_JWT")
check_code "$CODE" "200" "Queue position retrievable by staff"

echo ""
echo "=== 14. Staff check in patient ==="
CODE=$(req_code -X POST "$BASE_STAFF/queue/$APPT_ID/checkin" \
  -H "Authorization: Bearer $DOCTOR_JWT")
check_code "$CODE" "200" "Staff checked in patient"

echo ""
echo "=== 15. Call next patient ==="
CALL_RESP=$(req_json -X POST "$BASE_STAFF/queue/call-next" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $DOCTOR_JWT" \
  -d "{\"session\":\"$SESSION\",\"doctor_id\":\"$DOCTOR_ID\"}")
echo "$CALL_RESP" | jq .
CALLED_APPT=$(echo "$CALL_RESP" | jq -r '.appointment_id')
[ "$CALLED_APPT" = "$APPT_ID" ] && pass "Correct patient called next" || \
  fail "Called wrong appointment (got $CALLED_APPT, expected $APPT_ID)"

echo ""
echo "=== 16. Add consultation notes ==="
CODE=$(req_code -X POST "$BASE_STAFF/doctors/$APPT_ID/notes" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $DOCTOR_JWT" \
  -d "{\"patient_id\":\"$PATIENT_ID\",\"notes\":\"Patient presents with mild symptoms.\",\"diagnosis\":\"Common cold\"}")
check_code "$CODE" "200" "Consultation notes added"

echo ""
echo "=== 17. Complete appointment ==="
CODE=$(req_code -X PATCH "$BASE_STAFF/queue/$APPT_ID/complete" \
  -H "Authorization: Bearer $DOCTOR_JWT")
check_code "$CODE" "200" "Appointment completed"

echo ""
echo "=== 18. Verify queue entry removed (expect 404) ==="
CODE=$(req_code "$BASE_STAFF/queue/$APPT_ID/position" \
  -H "Authorization: Bearer $DOCTOR_JWT")
check_code "$CODE" "404" "Queue entry removed after completion"

# ── 6. No-show flow ───────────────────────────────────────────────────────────

echo ""
echo "=== 19. Book second appointment for no-show test ==="
DAYS2=$(( DAYS_AHEAD + 1 ))
HOUR2=$(( (HOUR + 1) % 17 + 9 ))
START_TIME2=$(date -u -v+${DAYS2}d "+%Y-%m-%dT$(printf '%02d' $HOUR2):00:00Z" 2>/dev/null || \
              date -u -d "+${DAYS2} days" "+%Y-%m-%dT$(printf '%02d' $HOUR2):00:00Z")

APPT2=$(curl -sf -X POST "$BASE_KONG/api/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $PATIENT_JWT" \
  -d "{\"patient_id\":\"$PATIENT_ID\",\"doctor_id\":\"$DOCTOR_ID\",\"start_time\":\"$START_TIME2\"}")
APPT_ID2=$(echo "$APPT2" | jq -r '.id // .appointment_id')
[ -z "$APPT_ID2" ] || [ "$APPT_ID2" = "null" ] && fail "Second booking failed"
pass "Second appointment booked (appt_id=$APPT_ID2)"

sleep 2

echo ""
echo "=== 20. Mark patient as no-show ==="
CODE=$(req_code -X PATCH "$BASE_STAFF/queue/$APPT_ID2/no-show" \
  -H "Authorization: Bearer $DOCTOR_JWT")
check_code "$CODE" "200" "Patient marked as no-show"

# ── 7. Remove from queue flow ─────────────────────────────────────────────────

echo ""
echo "=== 21. Book third appointment for remove-from-queue test ==="
DAYS3=$(( DAYS_AHEAD + 2 ))
START_TIME3=$(date -u -v+${DAYS3}d "+%Y-%m-%dT$(printf '%02d' $HOUR):00:00Z" 2>/dev/null || \
              date -u -d "+${DAYS3} days" "+%Y-%m-%dT$(printf '%02d' $HOUR):00:00Z")

APPT3=$(curl -sf -X POST "$BASE_KONG/api/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $PATIENT_JWT" \
  -d "{\"patient_id\":\"$PATIENT_ID\",\"doctor_id\":\"$DOCTOR_ID\",\"start_time\":\"$START_TIME3\"}")
APPT_ID3=$(echo "$APPT3" | jq -r '.id // .appointment_id')
[ -z "$APPT_ID3" ] || [ "$APPT_ID3" = "null" ] && fail "Third booking failed"
pass "Third appointment booked (appt_id=$APPT_ID3)"

sleep 2

echo ""
echo "=== 22. Remove patient from queue ==="
CODE=$(req_code -X DELETE "$BASE_STAFF/queue/$APPT_ID3" \
  -H "Authorization: Bearer $DOCTOR_JWT")
check_code "$CODE" "200" "Patient removed from queue"

echo ""
echo "=== 23. Verify removed patient no longer in queue ==="
CODE=$(req_code "$BASE_STAFF/queue/$APPT_ID3/position" \
  -H "Authorization: Bearer $DOCTOR_JWT")
check_code "$CODE" "404" "Removed patient not in queue"

echo ""
echo "=== All staff-orchestrator E2E tests passed! ==="
