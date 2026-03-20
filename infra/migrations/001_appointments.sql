CREATE SCHEMA IF NOT EXISTS appointments;

SET search_path TO appointments;

CREATE TABLE IF NOT EXISTS doctors (
    id              TEXT PRIMARY KEY,  -- BetterAuth nanoid (not UUID)
    name            TEXT NOT NULL,
    specialization  TEXT NOT NULL,
    slot_capacity   INT  NOT NULL DEFAULT 3,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS appointments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id      TEXT NOT NULL,
    doctor_id       TEXT REFERENCES doctors(id),
    start_time      TIMESTAMPTZ,                                       -- null for session-based bookings
    session         TEXT CHECK (session IN ('morning', 'afternoon')), -- null for specific doctor bookings
    estimated_time  TIMESTAMPTZ,
    queue_position  INT,
    notes           TEXT,
    status          TEXT NOT NULL DEFAULT 'scheduled',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT booking_type_valid CHECK (
        (session IS NOT NULL AND start_time IS NULL AND doctor_id IS NULL)
        OR
        (session IS NULL AND start_time IS NOT NULL AND doctor_id IS NOT NULL)
    )
);

-- No seed data — insert a doctor record after signing up via BetterAuth:
--   INSERT INTO appointments.doctors (id, name, specialization, slot_capacity)
--   VALUES ('<betterauth-nanoid>', 'Dr Test', 'General Practice', 3);

CREATE INDEX IF NOT EXISTS idx_appointments_doctor_start
    ON appointments(doctor_id, start_time)
    WHERE status NOT IN ('cancelled', 'no_show');

CREATE INDEX IF NOT EXISTS idx_appointments_patient
    ON appointments(patient_id);
