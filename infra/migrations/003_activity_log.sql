-- Activity log schema: records all clinic events for audit and patient history
CREATE SCHEMA IF NOT EXISTS activity_log;

SET search_path TO activity_log;

CREATE TABLE IF NOT EXISTS logs (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type      TEXT        NOT NULL,       -- e.g. appointment.booked, queue.called
    patient_id      TEXT        NOT NULL,
    appointment_id  TEXT,                        -- nullable (some events may not have one)
    actor           TEXT,                        -- who triggered event (patient, staff, system)
    payload         JSONB       NOT NULL DEFAULT '{}',  -- full event data
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Fast lookups by patient (for GET /patients/:id/history)
CREATE INDEX IF NOT EXISTS idx_logs_patient
    ON logs(patient_id, created_at DESC);

-- Fast lookups by event type (for analytics / filtering)
CREATE INDEX IF NOT EXISTS idx_logs_event_type
    ON logs(event_type, created_at DESC);

-- Fast lookups by appointment (to see full lifecycle of one appointment)
CREATE INDEX IF NOT EXISTS idx_logs_appointment
    ON logs(appointment_id)
    WHERE appointment_id IS NOT NULL;
