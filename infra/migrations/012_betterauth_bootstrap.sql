-- Bootstrap BetterAuth tables for local Docker auth-service usage.
-- Safe to run on existing databases.

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

CREATE TABLE IF NOT EXISTS betterauth.session (
    id           TEXT        PRIMARY KEY,
    "userId"     TEXT        NOT NULL REFERENCES betterauth."user"(id) ON DELETE CASCADE,
    token        TEXT        NOT NULL UNIQUE,
    "expiresAt"  TIMESTAMPTZ NOT NULL,
    "ipAddress"  TEXT,
    "userAgent"  TEXT,
    "createdAt"  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "updatedAt"  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_betterauth_session_user_id
    ON betterauth.session("userId");

CREATE TABLE IF NOT EXISTS betterauth.account (
    id                      TEXT        PRIMARY KEY,
    "accountId"             TEXT        NOT NULL,
    "providerId"            TEXT        NOT NULL,
    "userId"                TEXT        NOT NULL REFERENCES betterauth."user"(id) ON DELETE CASCADE,
    "accessToken"           TEXT,
    "refreshToken"          TEXT,
    "idToken"               TEXT,
    "accessTokenExpiresAt"  TIMESTAMPTZ,
    "refreshTokenExpiresAt" TIMESTAMPTZ,
    scope                   TEXT,
    password                TEXT,
    "createdAt"             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "updatedAt"             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_betterauth_account_provider UNIQUE ("providerId", "accountId")
);

CREATE INDEX IF NOT EXISTS idx_betterauth_account_user_id
    ON betterauth.account("userId");

CREATE TABLE IF NOT EXISTS betterauth.verification (
    id           TEXT        PRIMARY KEY,
    identifier   TEXT        NOT NULL,
    value        TEXT        NOT NULL,
    "expiresAt"  TIMESTAMPTZ NOT NULL,
    "createdAt"  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "updatedAt"  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_betterauth_verification_identifier
    ON betterauth.verification(identifier, "createdAt" DESC);

CREATE TABLE IF NOT EXISTS betterauth.jwks (
    id           TEXT        PRIMARY KEY,
    "publicKey"  TEXT        NOT NULL,
    "privateKey" TEXT        NOT NULL,
    "createdAt"  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "expiresAt"  TIMESTAMPTZ
);
