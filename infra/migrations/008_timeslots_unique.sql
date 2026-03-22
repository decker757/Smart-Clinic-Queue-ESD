-- Add unique constraint on (doctor_id, start_time) to support slot generation with ON CONFLICT DO NOTHING.
ALTER TABLE doctors.time_slots
    ADD CONSTRAINT uq_time_slots_doctor_start UNIQUE (doctor_id, start_time);
