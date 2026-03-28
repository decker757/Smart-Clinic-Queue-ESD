#!/bin/sh
# Seed multiple doctors and patients directly via AWS Cognito + RDS.
# Safe to re-run — skips Cognito users that already exist.
#
# Requires:
#   - aws CLI configured with ap-southeast-1 access
#   - psql available locally
#   - DATABASE_URL in infra/env/auth.env (RDS connection string)
#
# Usage: sh infra/scripts/seed-aws.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

POOL_ID="ap-southeast-1_3XvO4K1lI"
REGION="ap-southeast-1"
PASSWORD="Test1234!"   # Cognito requires upper+lower+digit+symbol

# Load DATABASE_URL, strip ?options=... if present
RAW_URL=$(grep "^DATABASE_URL=" "$REPO_ROOT/infra/env/auth.env" 2>/dev/null | cut -d= -f2-)
[ -z "$RAW_URL" ] && { echo "ERROR: DATABASE_URL not found in infra/env/auth.env"; exit 1; }
DB_URL=$(echo "$RAW_URL" | sed 's/?options=.*$//')

pass() { echo "  ✓ $1" >&2; }
skip() { echo "  - $1 (already exists)" >&2; }
fail() { echo "  ✗ FAIL: $1" >&2; exit 1; }

db_exec() {
  SCHEMA="$1"; SQL="$2"
  PGCONNECT_TIMEOUT=10 psql "$DB_URL" \
    -c "SET search_path TO $SCHEMA; SET statement_timeout = '10s'; $SQL" \
    -t -A 2>&1
}

# Create Cognito user + set permanent password + set custom:role
# Returns the Cognito sub (user ID)
ensure_cognito_user() {
  EMAIL="$1"; NAME="$2"; ROLE="$3"
  # Derive a simple username from the email local part (e.g. staff@clinic.com -> staff)
  USERNAME=$(echo "$EMAIL" | cut -d@ -f1)

  # Check if already exists
  echo "  [checking $USERNAME in Cognito...]" >&2
  EXISTING_SUB=$(aws cognito-idp admin-get-user \
    --user-pool-id "$POOL_ID" --username "$USERNAME" \
    --region "$REGION" \
    --cli-connect-timeout 10 \
    --cli-read-timeout 10 \
    --query "UserAttributes[?Name=='sub'].Value" \
    --output text 2>/dev/null || true)

  if [ -n "$EXISTING_SUB" ] && [ "$EXISTING_SUB" != "None" ]; then
    skip "$EMAIL (sub=$EXISTING_SUB)"
    echo "$EXISTING_SUB"
    return
  fi

  # Create user (suppress welcome email with SUPPRESS)
  echo "  [creating $USERNAME in Cognito...]" >&2
  aws cognito-idp admin-create-user \
    --user-pool-id "$POOL_ID" \
    --username "$USERNAME" \
    --user-attributes \
      Name=email,Value="$EMAIL" \
      Name=email_verified,Value=true \
      Name=name,Value="$NAME" \
      Name="custom:role",Value="$ROLE" \
    --message-action SUPPRESS \
    --region "$REGION" \
    --cli-connect-timeout 10 \
    --cli-read-timeout 10 > /dev/null

  # Set permanent password (avoids FORCE_CHANGE_PASSWORD state)
  echo "  [setting password for $USERNAME...]" >&2
  aws cognito-idp admin-set-user-password \
    --user-pool-id "$POOL_ID" \
    --username "$USERNAME" \
    --password "$PASSWORD" \
    --permanent \
    --region "$REGION" \
    --cli-connect-timeout 10 \
    --cli-read-timeout 10

  SUB=$(aws cognito-idp admin-get-user \
    --user-pool-id "$POOL_ID" --username "$USERNAME" \
    --region "$REGION" \
    --cli-connect-timeout 10 \
    --cli-read-timeout 10 \
    --query "UserAttributes[?Name=='sub'].Value" \
    --output text)

  pass "Created $EMAIL (sub=$SUB)"
  echo "$SUB"
}

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║       SEEDING AWS — DOCTORS & PATIENTS   ║"
echo "╚══════════════════════════════════════════╝"

# ── Staff ─────────────────────────────────────────────────────────────────────
echo ""
echo "━━━ Staff ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
STAFF_ID=$(ensure_cognito_user "staff@clinic.com" "Clinic Staff" "staff")
echo "  email: staff@clinic.com | password: $PASSWORD | sub: $STAFF_ID"

# ── Doctors ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━ Doctors ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

seed_doctor() {
  EMAIL="$1"; NAME="$2"; SPEC="$3"
  ID=$(ensure_cognito_user "$EMAIL" "$NAME" "doctor")
  db_exec doctors "INSERT INTO doctors (id, name, specialisation, contact)
                   VALUES ('$ID', '$NAME', '$SPEC', '$EMAIL')
                   ON CONFLICT (id) DO UPDATE SET
                     name = EXCLUDED.name,
                     specialisation = EXCLUDED.specialisation,
                     contact = EXCLUDED.contact" > /dev/null
  pass "doctors.doctors upserted"
  echo "  email: $EMAIL | password: $PASSWORD | specialisation: $SPEC | sub: $ID"
}

seed_doctor "doctor1@clinic.com" "Dr Alice Tan"  "General Practice"
seed_doctor "doctor2@clinic.com" "Dr Bob Lim"    "Cardiology"
seed_doctor "doctor3@clinic.com" "Dr Carol Wong" "Paediatrics"

# ── Patients ──────────────────────────────────────────────────────────────────
echo ""
echo "━━━ Patients ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

seed_patient() {
  EMAIL="$1"; NAME="$2"; PHONE="$3"; NRIC="$4"; DOB="$5"; GENDER="$6"
  ALLERGIES="$7"; [ -z "$ALLERGIES" ] && ALLERGIES="{}"
  echo "  [seed_patient: calling ensure_cognito_user for $EMAIL]" >&2
  ID=$(ensure_cognito_user "$EMAIL" "$NAME" "patient")
  echo "  [seed_patient: got ID=$ID, calling db_exec now]" >&2
  db_exec patients "INSERT INTO patients (id, phone, nric, dob, gender, allergies)
                    VALUES ('$ID', '$PHONE', '$NRIC', '$DOB', '$GENDER', '$ALLERGIES')
                    ON CONFLICT (id) DO UPDATE SET
                      phone = EXCLUDED.phone,
                      nric = EXCLUDED.nric,
                      dob = EXCLUDED.dob,
                      gender = EXCLUDED.gender,
                      allergies = EXCLUDED.allergies,
                      updated_at = NOW()"
  echo "  [seed_patient: db_exec done]" >&2
  pass "patients.patients upserted"
  echo "  email: $EMAIL | password: $PASSWORD | sub: $ID"
}

seed_patient "patient1@clinic.com" "John Smith"  "+6586527946" "S9012345A" "1990-03-15" "male"   "{Penicillin,Peanuts}"
seed_patient "patient2@clinic.com" "Sarah Lee"   "+6586527946" "S8523456B" "1985-07-22" "female" "{}"
seed_patient "patient3@clinic.com" "Raj Kumar"   "+6586527946" "S9534567C" "1995-11-08" "male"   "{}"
seed_patient "patient4@clinic.com" "Emily Ng"    "+6586527946" "S0045678D" "2000-01-30" "female" "{Aspirin,Shellfish,Latex}"
seed_patient "patient5@clinic.com" "Wei Chen"    "+6586527946" "S8756789E" "1987-05-19" "male"   "{Ibuprofen}"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║             SEED COMPLETE                ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "All accounts use password: $PASSWORD"
echo ""
