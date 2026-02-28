CREATE SCHEMA IF NOT EXISTS appointments;

SET search_path TO appointments;

CREATE TABLE IF NOT EXISTS doctors (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT NOT NULL,
    specialization  TEXT NOT NULL,
    slot_capacity   INT  NOT NULL DEFAULT 3,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS appointments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id      TEXT NOT NULL,
    doctor_id       UUID REFERENCES doctors(id),
    start_time      TIMESTAMPTZ NOT NULL,
    estimated_time  TIMESTAMPTZ,
    queue_position  INT,
    notes           TEXT,
    status          TEXT NOT NULL DEFAULT 'scheduled',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_appointments_doctor_start
    ON appointments(doctor_id, start_time)
    WHERE status NOT IN ('cancelled', 'no_show');

CREATE INDEX IF NOT EXISTS idx_appointments_patient
    ON appointments(patient_id);
