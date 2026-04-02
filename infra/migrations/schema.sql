-- Full schema for Smart Clinic Queue system.
-- Run once against a fresh Supabase database.
-- Consolidates migrations 001–009.

-- ─── BetterAuth ──────────────────────────────────────────────────────────────
-- Add role column to BetterAuth users table (created by BetterAuth on first run)
ALTER TABLE betterauth.user
    ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'patient';

-- ─── Appointments ────────────────────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS appointments;

CREATE TABLE IF NOT EXISTS appointments.doctors (
    id             TEXT        PRIMARY KEY,  -- BetterAuth nanoid
    name           TEXT        NOT NULL,
    specialization TEXT        NOT NULL,
    slot_capacity  INT         NOT NULL DEFAULT 1,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS appointments.appointments (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id     TEXT        NOT NULL,
    doctor_id      TEXT        REFERENCES appointments.doctors(id),
    start_time     TIMESTAMPTZ,
    session        TEXT        CHECK (session IN ('morning', 'afternoon')),
    estimated_time TIMESTAMPTZ,
    queue_position INT,
    notes          TEXT,
    status         TEXT        NOT NULL DEFAULT 'scheduled',
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT booking_type_valid CHECK (
        (session IS NOT NULL AND start_time IS NULL AND doctor_id IS NULL)
        OR
        (session IS NULL AND start_time IS NOT NULL AND doctor_id IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_appointments_doctor_start
    ON appointments.appointments(doctor_id, start_time)
    WHERE status NOT IN ('cancelled', 'no_show');

CREATE INDEX IF NOT EXISTS idx_appointments_patient
    ON appointments.appointments(patient_id);

-- ─── Queue ───────────────────────────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS queue;

CREATE TABLE IF NOT EXISTS queue.queue_entries (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    appointment_id TEXT        NOT NULL UNIQUE,
    patient_id     TEXT        NOT NULL,
    doctor_id      TEXT,
    session        TEXT        CHECK (session IN ('morning', 'afternoon')),
    queue_number   INT         NOT NULL,
    status         TEXT        NOT NULL DEFAULT 'waiting'
                               CHECK (status IN ('waiting', 'checked_in', 'called', 'in_progress', 'done', 'skipped', 'cancelled')),
    estimated_time           TIMESTAMPTZ,
    approaching_notified_at  TIMESTAMPTZ,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE SEQUENCE IF NOT EXISTS queue.queue_number_morning_seq START 1;
CREATE SEQUENCE IF NOT EXISTS queue.queue_number_afternoon_seq START 1;

CREATE INDEX IF NOT EXISTS idx_queue_session_status ON queue.queue_entries(session, status);
CREATE INDEX IF NOT EXISTS idx_queue_patient        ON queue.queue_entries(patient_id);
CREATE INDEX IF NOT EXISTS idx_queue_number         ON queue.queue_entries(queue_number);
CREATE INDEX IF NOT EXISTS idx_queue_status_doctor  ON queue.queue_entries(status, doctor_id) WHERE doctor_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_queue_status_session ON queue.queue_entries(status, session)    WHERE session IS NOT NULL;

-- ─── Activity Log ────────────────────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS activity_log;

CREATE TABLE IF NOT EXISTS activity_log.logs (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type     TEXT        NOT NULL,
    patient_id     TEXT        NOT NULL,
    appointment_id TEXT,
    actor          TEXT,
    payload        JSONB       NOT NULL DEFAULT '{}',
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_logs_patient
    ON activity_log.logs(patient_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_logs_event_type
    ON activity_log.logs(event_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_logs_appointment
    ON activity_log.logs(appointment_id)
    WHERE appointment_id IS NOT NULL;

-- ─── Patients ────────────────────────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS patients;

CREATE TABLE IF NOT EXISTS patients.patients (
    id         TEXT        PRIMARY KEY,  -- BetterAuth nanoid
    phone      TEXT,
    dob        DATE,
    nric       TEXT,
    gender     TEXT,
    allergies  TEXT[]      NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS patients.medical_history (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id   TEXT        NOT NULL REFERENCES patients.patients(id),
    diagnosis    TEXT        NOT NULL,
    diagnosed_at DATE,
    notes        TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS patients.memos (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id     TEXT        NOT NULL REFERENCES patients.patients(id),
    title          TEXT        NOT NULL,
    content        TEXT,
    file_url       TEXT,
    file_type      TEXT,
    record_type    TEXT        NOT NULL DEFAULT 'memo',
    issued_by      TEXT,
    appointment_id TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_medical_history_patient ON patients.medical_history(patient_id);
CREATE INDEX IF NOT EXISTS idx_memos_patient           ON patients.memos(patient_id);

-- ─── Doctors ─────────────────────────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS doctors;

CREATE TABLE IF NOT EXISTS doctors.doctors (
    id            TEXT        PRIMARY KEY,  -- BetterAuth nanoid
    name          VARCHAR(255) NOT NULL,
    specialisation VARCHAR(255),
    contact       VARCHAR(100),
    created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- Sync new doctors into appointments.doctors so the FK on
-- appointments.appointments.doctor_id is always satisfiable.
CREATE OR REPLACE FUNCTION doctors.sync_to_appointments()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO appointments.doctors (id, name, specialization, slot_capacity)
    VALUES (NEW.id, NEW.name, COALESCE(NEW.specialisation, ''), 1)
    ON CONFLICT (id) DO UPDATE
        SET name = EXCLUDED.name,
            specialization = EXCLUDED.specialization;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_doctor_to_appointments ON doctors.doctors;
CREATE TRIGGER trg_sync_doctor_to_appointments
    AFTER INSERT OR UPDATE ON doctors.doctors
    FOR EACH ROW EXECUTE FUNCTION doctors.sync_to_appointments();

CREATE TABLE IF NOT EXISTS doctors.time_slots (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    doctor_id  TEXT        REFERENCES doctors.doctors(id),
    start_time TIMESTAMPTZ NOT NULL,
    end_time   TIMESTAMPTZ NOT NULL,
    status     VARCHAR(50) DEFAULT 'available',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT uq_time_slots_doctor_start UNIQUE (doctor_id, start_time)
);

CREATE TABLE IF NOT EXISTS doctors.consultations (
    id             UUID   PRIMARY KEY DEFAULT gen_random_uuid(),
    appointment_id UUID   UNIQUE,
    doctor_id      TEXT   REFERENCES doctors.doctors(id),
    patient_id     TEXT   NOT NULL,
    notes          TEXT,
    diagnosis      TEXT,
    created_at     TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_consultations_patient ON doctors.consultations(patient_id);
CREATE INDEX IF NOT EXISTS idx_consultations_doctor  ON doctors.consultations(doctor_id);

-- ─── Payments ────────────────────────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS payments;

CREATE TABLE IF NOT EXISTS payments.payments (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    consultation_id   TEXT        NOT NULL,
    patient_id        TEXT        NOT NULL,
    payment_intent_id TEXT,
    status            TEXT        NOT NULL,  -- 'pending' | 'paid' | 'failed'
    payment_link      TEXT,
    created_at        TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payments_consultation ON payments.payments(consultation_id);
CREATE INDEX IF NOT EXISTS idx_payments_patient      ON payments.payments(patient_id);
