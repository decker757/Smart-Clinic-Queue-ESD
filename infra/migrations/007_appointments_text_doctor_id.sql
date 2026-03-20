-- Fix appointments.doctors.id and appointments.doctor_id to TEXT
-- to accept BetterAuth nanoid user IDs (not valid UUIDs).
-- Run once if 001_appointments.sql was already applied with UUID columns.

SET search_path TO appointments;

-- Drop FK constraint before altering
ALTER TABLE appointments DROP CONSTRAINT IF EXISTS appointments_doctor_id_fkey;

-- Change doctors.id to TEXT
ALTER TABLE doctors
    ALTER COLUMN id DROP DEFAULT,
    ALTER COLUMN id TYPE TEXT USING id::TEXT;

-- Change appointments.doctor_id to TEXT
ALTER TABLE appointments
    ALTER COLUMN doctor_id TYPE TEXT USING doctor_id::TEXT;

-- Re-add FK
ALTER TABLE appointments
    ADD CONSTRAINT appointments_doctor_id_fkey
    FOREIGN KEY (doctor_id) REFERENCES doctors(id);

-- Remove old UUID-based seed doctor if present
DELETE FROM doctors WHERE id = 'a0000000-0000-0000-0000-000000000001';
