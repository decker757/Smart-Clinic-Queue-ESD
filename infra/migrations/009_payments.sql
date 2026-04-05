-- Payment Service Schema

CREATE SCHEMA IF NOT EXISTS payments;

CREATE TABLE IF NOT EXISTS payments.payments (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    consultation_id  TEXT        NOT NULL,   -- appointment_id from consultation
    patient_id       TEXT        NOT NULL,
    payment_intent_id TEXT,                  -- Stripe PaymentIntent ID
    status           TEXT        NOT NULL,   -- 'pending' | 'paid' | 'failed'
    payment_link     TEXT,
    created_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payments_consultation ON payments.payments(consultation_id);
CREATE INDEX IF NOT EXISTS idx_payments_patient      ON payments.payments(patient_id);
