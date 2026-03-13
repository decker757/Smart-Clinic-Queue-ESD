CREATE SCHEMA IF NOT EXISTS patients;

CREATE TABLE IF NOT EXISTS patients.patients (
    id          TEXT PRIMARY KEY,
    phone       TEXT,
    dob         DATE,
    nric        TEXT,
    gender      TEXT,
    allergies   TEXT[]          NOT NULL DEFAULT '{}',
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS patients.medical_history (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id      TEXT        NOT NULL REFERENCES patients.patients(id),
    diagnosis       TEXT        NOT NULL,
    diagnosed_at    DATE,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS patients.memos (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id  TEXT        NOT NULL REFERENCES patients.patients(id),
    title       TEXT        NOT NULL,
    content     TEXT,
    file_url    TEXT,
    file_type   TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_medical_history_patient ON patients.medical_history(patient_id);
CREATE INDEX IF NOT EXISTS idx_memos_patient ON patients.memos(patient_id);
