CREATE TABLE appointments(
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id  UUID NOT NULL,
    doctor_id   UUID NOT NULL,
    start_time  TIMESTAMPTZ NOT NULL,
    status      TEXT NOT NULL DEFAULT 'scheduled',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(doctor_id, start_time)
);