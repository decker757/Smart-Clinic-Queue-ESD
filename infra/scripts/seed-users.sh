#!/bin/sh
# Seed test user accounts: 1 doctor, 1 staff, 1 patient.
# Safe to re-run — skips accounts that already exist.
#
# Requires:
#   - auth-service running (localhost:3000)
#   - app-db running for local Docker mode
#   - psql available locally OR Docker (for external DB mode)
#   - DATABASE_URL readable from infra/env/auth.env
#
# Usage: sh infra/scripts/seed-users.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/infra/docker-compose.yml"

AUTH="http://localhost:3000/api/auth"

# Load DATABASE_URL from auth.env.
# Strip ?options=... — psql rejects that query param; we SET search_path manually instead.
RAW_URL=$(grep "^DATABASE_URL=" "$REPO_ROOT/infra/env/auth.env" 2>/dev/null | cut -d= -f2-)
if [ -z "$RAW_URL" ]; then
  echo "ERROR: DATABASE_URL not found in infra/env/auth.env"
  exit 1
fi
DATABASE_URL=$(echo "$RAW_URL" | sed 's/?options=.*$//')

LOCAL_DOCKER_DB=false
case "$RAW_URL" in
  *@app-db:*)
    LOCAL_DOCKER_DB=true
    ;;
esac

pass() { echo "  ✓ $1"; }
skip() { echo "  - $1 (already exists)"; }
fail() { echo "  ✗ FAIL: $1"; exit 1; }

# Run SQL against the configured DB, using docker compose exec for local Docker mode.
db_exec() {
  SQL="$1"
  if [ "$LOCAL_DOCKER_DB" = "true" ]; then
    docker compose -f "$COMPOSE_FILE" exec -T app-db \
      psql -U app -d clinic -v ON_ERROR_STOP=1 -q -c "$SQL" -t -A 2>/dev/null
  elif command -v psql >/dev/null 2>&1; then
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -c "$SQL" -t -A 2>/dev/null
  else
    docker run --rm postgres:16-alpine \
      psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -c "$SQL" -t -A 2>/dev/null
  fi
}

supabase_exec() {
  db_exec "$1"
}

doctors_exec() {
  db_exec "$1"
}

appt_exec() {
  db_exec "$1"
}

signup() {
  EMAIL="$1"; PASSWORD="$2"; NAME="$3"
  RESP=$(curl -sf -X POST "$AUTH/sign-up/email" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"name\":\"$NAME\"}")
  echo "$RESP" | jq -r '.user.id // empty'
}

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║          SEEDING TEST USERS              ║"
echo "╚══════════════════════════════════════════╝"

if [ "$LOCAL_DOCKER_DB" = "true" ]; then
  pass "Using local Docker app-db via docker compose exec"
else
  pass "Using DATABASE_URL from infra/env/auth.env"
fi

# ── Doctor ────────────────────────────────────────────────────────────────────
echo ""
echo "━━━ Doctor ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
DOCTOR_EMAIL="doctor@clinic.com"
DOCTOR_PASSWORD="password123"
DOCTOR_NAME="Dr Test"

EXISTING=$(supabase_exec "SELECT id FROM betterauth.\"user\" WHERE email = '$DOCTOR_EMAIL'")
if [ -n "$EXISTING" ]; then
  DOCTOR_ID="$EXISTING"
  skip "Doctor account already exists (id=$DOCTOR_ID)"
else
  DOCTOR_ID=$(signup "$DOCTOR_EMAIL" "$DOCTOR_PASSWORD" "$DOCTOR_NAME")
  [ -z "$DOCTOR_ID" ] && fail "Doctor sign-up failed"
  pass "Doctor account created (id=$DOCTOR_ID)"
fi

supabase_exec "UPDATE betterauth.\"user\" SET role = 'doctor' WHERE id = '$DOCTOR_ID'" > /dev/null
pass "Role set to 'doctor'"

doctors_exec "INSERT INTO doctors.doctors (id, name, specialisation, contact)
              VALUES ('$DOCTOR_ID', '$DOCTOR_NAME', 'General Practice', 'doctor@clinic.com')
              ON CONFLICT (id) DO NOTHING" > /dev/null
pass "doctors.doctors record upserted"

# Also insert into appointments.doctors so the FK on appointments.appointments.doctor_id works
appt_exec "INSERT INTO appointments.doctors (id, name, specialization, slot_capacity)
           VALUES ('$DOCTOR_ID', '$DOCTOR_NAME', 'General Practice', 1)
           ON CONFLICT (id) DO NOTHING" > /dev/null
pass "appointments.doctors record upserted (FK sync)"

echo "  email:    $DOCTOR_EMAIL"
echo "  password: $DOCTOR_PASSWORD"
echo "  user_id:  $DOCTOR_ID"

# ── Staff ─────────────────────────────────────────────────────────────────────
echo ""
echo "━━━ Staff ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
STAFF_EMAIL="staff@clinic.com"
STAFF_PASSWORD="password123"
STAFF_NAME="Clinic Staff"

EXISTING=$(supabase_exec "SELECT id FROM betterauth.\"user\" WHERE email = '$STAFF_EMAIL'")
if [ -n "$EXISTING" ]; then
  STAFF_ID="$EXISTING"
  skip "Staff account already exists (id=$STAFF_ID)"
else
  STAFF_ID=$(signup "$STAFF_EMAIL" "$STAFF_PASSWORD" "$STAFF_NAME")
  [ -z "$STAFF_ID" ] && fail "Staff sign-up failed"
  pass "Staff account created (id=$STAFF_ID)"
fi

supabase_exec "UPDATE betterauth.\"user\" SET role = 'staff' WHERE id = '$STAFF_ID'" > /dev/null
pass "Role set to 'staff'"

echo "  email:    $STAFF_EMAIL"
echo "  password: $STAFF_PASSWORD"
echo "  user_id:  $STAFF_ID"

# ── Patient ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━ Patient ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
PATIENT_EMAIL="patient@clinic.com"
PATIENT_PASSWORD="password123"
PATIENT_NAME="Test Patient"

EXISTING=$(supabase_exec "SELECT id FROM betterauth.\"user\" WHERE email = '$PATIENT_EMAIL'")
if [ -n "$EXISTING" ]; then
  PATIENT_ID="$EXISTING"
  skip "Patient account already exists (id=$PATIENT_ID)"
else
  PATIENT_ID=$(signup "$PATIENT_EMAIL" "$PATIENT_PASSWORD" "$PATIENT_NAME")
  [ -z "$PATIENT_ID" ] && fail "Patient sign-up failed"
  pass "Patient account created (id=$PATIENT_ID)"
fi
pass "Role = 'patient' (default)"

echo "  email:    $PATIENT_EMAIL"
echo "  password: $PATIENT_PASSWORD"
echo "  user_id:  $PATIENT_ID"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║             SEED COMPLETE                ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "Credentials for E2E tests:"
echo ""
echo "  export DOCTOR_EMAIL=$DOCTOR_EMAIL DOCTOR_PASSWORD=$DOCTOR_PASSWORD"
echo "  export STAFF_EMAIL=$STAFF_EMAIL   STAFF_PASSWORD=$STAFF_PASSWORD"
echo "  export PATIENT_EMAIL=$PATIENT_EMAIL PATIENT_PASSWORD=$PATIENT_PASSWORD"
echo ""
echo "Run consultation E2E test:"
echo "  export DOCTOR_EMAIL=$DOCTOR_EMAIL DOCTOR_PASSWORD=$DOCTOR_PASSWORD"
echo "  sh infra/tests/test-consultation.sh"
