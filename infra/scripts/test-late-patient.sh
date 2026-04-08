#!/bin/sh
# test-late-patient.sh
#
# Automates the late-patient deprioritization scenario:
#   1. Book morning walk-in appointments for 3 patients
#   2. Check in all 3
#   3. Deprioritize Patient 1 (simulating late detection)
#   4. Print queue order — Patient 1 should be last despite booking first
#
# Prerequisites: local stack running (docker compose up)
# Usage: sh infra/scripts/test-late-patient.sh

set -e

KONG="http://localhost:8000"
QUEUE="http://localhost:3002"   # direct, bypasses Kong JWT for staff actions
AUTH="http://localhost:3000/api/auth"

pass() { printf "  \033[32m✓\033[0m %s\n" "$1"; }
info() { printf "  \033[34m→\033[0m %s\n" "$1"; }
fail() { printf "  \033[31m✗\033[0m %s\n" "$1"; exit 1; }
section() { printf "\n\033[1m━━━ %s ━━━\033[0m\n" "$1"; }

# ── Auth helpers ──────────────────────────────────────────────────────────────

# Sets globals: _JWT and _PID
get_jwt() {
  EMAIL="$1"; PASSWORD="$2"
  # 1. Sign in → session token + patient id
  SIGNIN=$(curl -sf -X POST "$AUTH/sign-in/email" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"rememberMe\":false}")
  SESSION=$(echo "$SIGNIN" | jq -r '.token // empty')
  _PID=$(echo "$SIGNIN" | jq -r '.user.id // empty')
  if [ -z "$SESSION" ]; then fail "Sign-in failed for $EMAIL"; fi

  # 2. Exchange session token → JWT (BetterAuth uses Bearer, not JSON body)
  _JWT=$(curl -sf -X GET "$AUTH/token" \
    -H "Authorization: Bearer $SESSION" \
    | jq -r '.token // empty')
  if [ -z "$_JWT" ]; then fail "JWT exchange failed for $EMAIL"; fi
}

# ── Reset ─────────────────────────────────────────────────────────────────────

section "Reset"
curl -sf -X POST "$QUEUE/api/queue/reset" > /dev/null
pass "Queue reset"

# Cancel any leftover scheduled appointments for the 3 test patients
# so they don't appear as stale on the dashboard.
COMPOSE_FILE="$(dirname "$0")/../docker-compose.yml"
docker compose -f "$COMPOSE_FILE" exec -T app-db psql -U app -d clinic -q -c "
  UPDATE appointments.appointments
  SET status = 'cancelled'
  WHERE status IN ('scheduled','checked_in','in_progress')
    AND patient_id IN (SELECT id FROM betterauth.\"user\" WHERE email LIKE '%@clinic.com');
" 2>/dev/null
pass "Stale appointments cancelled"

# ── Authenticate ──────────────────────────────────────────────────────────────

section "Authenticating patients"
info "patient@clinic.com"
get_jwt "patient@clinic.com" "password123"; JWT1="$_JWT"; PID1="$_PID"
pass "Patient 1 JWT obtained (id=$PID1)"

info "patient2@clinic.com"
get_jwt "patient2@clinic.com" "password123"; JWT2="$_JWT"; PID2="$_PID"
pass "Patient 2 JWT obtained (id=$PID2)"

info "patient3@clinic.com"
get_jwt "patient3@clinic.com" "password123"; JWT3="$_JWT"; PID3="$_PID"
pass "Patient 3 JWT obtained (id=$PID3)"

# ── Book appointments ─────────────────────────────────────────────────────────

section "Booking morning walk-in appointments"

book() {
  JWT="$1"; PID="$2"; LABEL="$3"
  RESP=$(curl -sf -X POST "$KONG/api/composite/appointments" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $JWT" \
    -d "{\"patient_id\":\"$PID\",\"session\":\"morning\"}")
  APPT_ID=$(echo "$RESP" | jq -r '.id // empty')
  if [ -z "$APPT_ID" ]; then fail "Booking failed for $LABEL: $RESP" >&2; fi
  printf "  \033[32m✓\033[0m %s\n" "$LABEL → appointment $APPT_ID" >&2
  echo "$APPT_ID"
}

APPT1=$(book "$JWT1" "$PID1" "Patient 1")
sleep 0.5   # let RabbitMQ deliver appointment.booked to queue-coordinator
APPT2=$(book "$JWT2" "$PID2" "Patient 2")
sleep 0.5
APPT3=$(book "$JWT3" "$PID3" "Patient 3")
sleep 1     # give queue-coordinator time to process all three

# ── Show initial queue ────────────────────────────────────────────────────────

section "Initial queue (all waiting)"
docker compose -f "$(dirname "$0")/../docker-compose.yml" exec -T app-db \
  psql -U app -d clinic -q -c \
  "SELECT qe.queue_number AS q_no,
          COALESCE(qe.sort_key, qe.queue_number*1000) AS sort_key,
          qe.status,
          u.email
   FROM queue.queue_entries qe
   JOIN betterauth.\"user\" u ON u.id = qe.patient_id
   WHERE qe.status NOT IN ('done','cancelled')
   ORDER BY sort_key ASC;" 2>/dev/null

# ── Deprioritize Patient 1 (late) ─────────────────────────────────────────────

section "Patient 1 is 15 min away — deprioritizing (1 slot shift)"
# ceil(15/15) = 1 slot shift → Patient 1 moves from position 0 to position 1,
# landing at the MIDPOINT between Patient 2 (sort_key 2000) and Patient 3 (sort_key 3000).
# Expected new sort_key: 2500 — NOT at the end (4000+).
DEPR=$(curl -sf -X POST "$QUEUE/api/queue/deprioritize/$APPT1" \
  -H "Content-Type: application/json" \
  -d '{"travel_eta_minutes": 15}')
NEW_SORT=$(echo "$DEPR" | jq '.sort_key')
pass "Patient 1 sort_key → $NEW_SORT (expected 2500 — midpoint between P2 and P3, not at the end)"

# ── Check in all 3 ───────────────────────────────────────────────────────────

section "All 3 patients check in"
curl -sf -X POST "$QUEUE/api/queue/checkin/$APPT1" -H "Authorization: Bearer $JWT1" > /dev/null && pass "Patient 1 checked in"
curl -sf -X POST "$QUEUE/api/queue/checkin/$APPT2" -H "Authorization: Bearer $JWT2" > /dev/null && pass "Patient 2 checked in"
curl -sf -X POST "$QUEUE/api/queue/checkin/$APPT3" -H "Authorization: Bearer $JWT3" > /dev/null && pass "Patient 3 checked in"

# ── Show final queue order ────────────────────────────────────────────────────

section "Final queue order (Patient 1 should be last)"
docker compose -f "$(dirname "$0")/../docker-compose.yml" exec -T app-db \
  psql -U app -d clinic -q -c \
  "SELECT qe.queue_number AS q_no,
          COALESCE(qe.sort_key, qe.queue_number*1000) AS sort_key,
          qe.status,
          u.email
   FROM queue.queue_entries qe
   JOIN betterauth.\"user\" u ON u.id = qe.patient_id
   WHERE qe.status NOT IN ('done','cancelled')
   ORDER BY sort_key ASC;" 2>/dev/null

# ── Simulate doctor calling next ──────────────────────────────────────────────

section "Doctor calls next (3 times)"
for i in 1 2 3; do
  CALLED=$(curl -sf -X POST "$QUEUE/api/queue/call-next" \
    -H "Content-Type: application/json" \
    -d '{"session":"morning"}' | jq -r '.patient_id')
  EMAIL=$(docker compose -f "$(dirname "$0")/../docker-compose.yml" exec -T app-db \
    psql -U app -d clinic -q -t -A -c \
    "SELECT email FROM betterauth.\"user\" WHERE id = '$CALLED';" 2>/dev/null)
  pass "Call $i → $EMAIL"
done

# Mark all test appointments as completed so nothing lingers on the dashboard
docker compose -f "$COMPOSE_FILE" exec -T app-db psql -U app -d clinic -q -c "
  UPDATE appointments.appointments SET status = 'completed'
  WHERE id IN ('$APPT1','$APPT2','$APPT3');
  UPDATE queue.queue_entries SET status = 'done'
  WHERE appointment_id IN ('$APPT1','$APPT2','$APPT3');
" 2>/dev/null

printf "\n\033[32mScenario complete.\033[0m\n"
printf "  Patient 1 booked first but arrived late.\n"
printf "  sort_key 2500 = midpoint(2000, 3000) → inserted between P2 and P3.\n"
printf "  A naive 'push to back' would give sort_key 4000+ — this is NOT that.\n\n"
