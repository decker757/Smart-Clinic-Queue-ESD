-- Consultation completion outbox: repurpose doctors.consultations as the
-- idempotency gate by adding completion_status and payment_link columns.
-- Also makes MC/prescription and medical-history writes idempotent so that
-- retrying a failed consultation completion cannot create duplicate records.

-- ── Consultation outbox columns ───────────────────────────────────────────────
ALTER TABLE doctors.consultations
    ADD COLUMN IF NOT EXISTS completion_status TEXT NOT NULL DEFAULT 'processing'
        CHECK (completion_status IN ('processing', 'completed', 'failed')),
    ADD COLUMN IF NOT EXISTS payment_link TEXT;

-- ── Memos idempotency: one MC and one prescription per appointment ────────────
CREATE UNIQUE INDEX IF NOT EXISTS uq_memos_appointment_record_type
    ON patients.memos (appointment_id, record_type)
    WHERE appointment_id IS NOT NULL;

-- ── Medical history idempotency: one history entry per appointment ────────────
ALTER TABLE patients.medical_history
    ADD COLUMN IF NOT EXISTS appointment_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS uq_history_appointment
    ON patients.medical_history (appointment_id)
    WHERE appointment_id IS NOT NULL;
