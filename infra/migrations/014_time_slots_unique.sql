-- Add unique constraint on (doctor_id, start_time) to doctors.time_slots so that
-- ON CONFLICT (doctor_id, start_time) DO NOTHING in generateSlots() works correctly
-- on databases upgraded from earlier migrations (the constraint only existed in schema.sql).

ALTER TABLE doctors.time_slots
    ADD CONSTRAINT IF NOT EXISTS uq_time_slots_doctor_start UNIQUE (doctor_id, start_time);
