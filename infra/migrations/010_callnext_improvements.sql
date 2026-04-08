-- Fix slot_capacity default to 1 (was 3) — one patient per 15-min specific-doctor slot.
-- Update existing doctor rows so the new default is applied to live data.
ALTER TABLE appointments.doctors ALTER COLUMN slot_capacity SET DEFAULT 1;
UPDATE appointments.doctors SET slot_capacity = 1 WHERE slot_capacity = 3;

-- Partial indexes for callNext WHERE clause paths.
-- (status, doctor_id) covers the specific-doctor booking filter.
-- (status, session)   covers the generic queue filter.
CREATE INDEX IF NOT EXISTS idx_queue_status_doctor
    ON queue.queue_entries(status, doctor_id)
    WHERE doctor_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_queue_status_session
    ON queue.queue_entries(status, session)
    WHERE session IS NOT NULL;
