-- Add ordering and arrival-tracking fields required by the queue coordinator's
-- late-patient handling. Backfill existing rows so older environments can
-- upgrade in-place without recreating the database.

ALTER TABLE queue.queue_entries
    ADD COLUMN IF NOT EXISTS sort_key BIGINT;

UPDATE queue.queue_entries
SET sort_key = queue_number * 1000
WHERE sort_key IS NULL OR sort_key = 0;

ALTER TABLE queue.queue_entries
    ALTER COLUMN sort_key SET DEFAULT 0;

ALTER TABLE queue.queue_entries
    ALTER COLUMN sort_key SET NOT NULL;

ALTER TABLE queue.queue_entries
    ADD COLUMN IF NOT EXISTS estimated_arrival_at TIMESTAMPTZ;

ALTER TABLE queue.queue_entries
    ADD COLUMN IF NOT EXISTS approaching_notified_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_queue_sort_key
    ON queue.queue_entries(sort_key);
