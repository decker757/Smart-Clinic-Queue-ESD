-- Add role field to BetterAuth users table
-- Roles: patient (default), doctor, staff, admin

CREATE SCHEMA IF NOT EXISTS betterauth;

CREATE TABLE IF NOT EXISTS betterauth."user" (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    email           TEXT NOT NULL UNIQUE,
    "emailVerified" BOOLEAN NOT NULL DEFAULT FALSE,
    image           TEXT,
    role            TEXT NOT NULL DEFAULT 'patient',
    "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "updatedAt"     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE betterauth."user"
    ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'patient';
