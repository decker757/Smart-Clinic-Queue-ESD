CREATE SCHEMA IF NOT EXISTS queue;

SET search_path TO queue;

CREATE TABLE IF NOT EXISTS queue_entries (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    appointment_id  TEXT        NOT NULL UNIQUE,
    patient_id      TEXT        NOT NULL,
    doctor_id       UUID,                                                    -- null until assigned (generic bookings)
    session         TEXT        CHECK (session IN ('morning', 'afternoon')), -- null for specific doctor bookings
    queue_number    INT         NOT NULL,
    status          TEXT        NOT NULL DEFAULT 'waiting'
                                CHECK (status IN ('waiting', 'called', 'in_progress', 'done', 'skipped')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- separate sequences for morning and afternoon queues, reset daily via application logic
CREATE SEQUENCE IF NOT EXISTS queue_number_morning_seq START 1;
CREATE SEQUENCE IF NOT EXISTS queue_number_afternoon_seq START 1;

CREATE INDEX IF NOT EXISTS idx_queue_session_status
    ON queue_entries(session, status);

CREATE INDEX IF NOT EXISTS idx_queue_patient
    ON queue_entries(patient_id);

CREATE INDEX IF NOT EXISTS idx_queue_number
    ON queue_entries(queue_number);
