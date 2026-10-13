-- NexaBank IdentityForge — PostgreSQL Schema
-- Run by docker-entrypoint-initdb.d on first container start

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Audit log (mirror of API audit middleware output, for queryable storage)
CREATE TABLE IF NOT EXISTS audit_events (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event         TEXT NOT NULL,
    user_id       TEXT,
    realm         TEXT,
    client_cert   TEXT,
    method        TEXT,
    path          TEXT,
    status_code   INTEGER,
    latency_ms    INTEGER,
    ip            TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_user_id ON audit_events (user_id);
CREATE INDEX IF NOT EXISTS idx_audit_created_at ON audit_events (created_at DESC);

-- Agent device registry
CREATE TABLE IF NOT EXISTS agent_devices (
    agent_id      TEXT PRIMARY KEY,
    cert_serial   TEXT,
    branch_code   TEXT,
    region        TEXT,
    provisioned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at    TIMESTAMPTZ,
    offboarded_at TIMESTAMPTZ
);

-- Partner registry
CREATE TABLE IF NOT EXISTS partners (
    partner_id    TEXT PRIMARY KEY,
    mfb_code      TEXT UNIQUE NOT NULL,
    name          TEXT NOT NULL,
    cert_serial   TEXT,
    active        BOOLEAN NOT NULL DEFAULT TRUE,
    registered_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Transactions (stub — extend with your business logic)
CREATE TABLE IF NOT EXISTS transactions (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    initiated_by  TEXT NOT NULL,        -- Keycloak sub
    realm         TEXT NOT NULL,
    amount        NUMERIC(18, 2) NOT NULL,
    currency      TEXT NOT NULL DEFAULT 'NGN',
    to_account    TEXT NOT NULL,
    status        TEXT NOT NULL DEFAULT 'pending',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
