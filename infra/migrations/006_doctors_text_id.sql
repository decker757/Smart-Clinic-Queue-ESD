-- Fix doctors.id to TEXT to accept BetterAuth nanoid user IDs (not valid UUIDs).
-- Run this once if 005_doctors.sql was already applied with UUID columns.

-- Drop FK constraints before altering column types
ALTER TABLE doctors.time_slots    DROP CONSTRAINT IF EXISTS time_slots_doctor_id_fkey;
ALTER TABLE doctors.consultations  DROP CONSTRAINT IF EXISTS consultations_doctor_id_fkey;

-- Change id on doctors table
ALTER TABLE doctors.doctors
    ALTER COLUMN id DROP DEFAULT,
    ALTER COLUMN id TYPE TEXT USING id::TEXT;

-- Change doctor_id on dependent tables
ALTER TABLE doctors.time_slots
    ALTER COLUMN doctor_id TYPE TEXT USING doctor_id::TEXT;

ALTER TABLE doctors.consultations
    ALTER COLUMN doctor_id TYPE TEXT USING doctor_id::TEXT;

-- Re-add FK constraints
ALTER TABLE doctors.time_slots
    ADD CONSTRAINT time_slots_doctor_id_fkey
    FOREIGN KEY (doctor_id) REFERENCES doctors.doctors(id);

ALTER TABLE doctors.consultations
    ADD CONSTRAINT consultations_doctor_id_fkey
    FOREIGN KEY (doctor_id) REFERENCES doctors.doctors(id);
