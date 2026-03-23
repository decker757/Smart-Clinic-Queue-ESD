-- Add role field to BetterAuth users table
-- Roles: patient (default), doctor, staff, admin

ALTER TABLE betterauth.user
    ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'patient';
