-- EDL Manager schema (PostgreSQL 13+)
-- Run with: psql "$DATABASE_URL" -f schema.sql

CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- for gen_random_uuid() on older servers

-- ----------------------------------------------------------------------------
-- Users (minimal; keyed on the OIDC subject claim)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  oidc_sub      text UNIQUE NOT NULL,
  email         text,
  display_name  text,
  role          text NOT NULL DEFAULT 'editor'
                  CHECK (role IN ('admin', 'editor', 'viewer')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  last_login_at timestamptz
);

-- ----------------------------------------------------------------------------
-- EDLs. `slug` is what appears in the public URL: /edl/<slug>.txt
-- `owner` is intentionally nullable and unused in single-tenant mode; it is the
-- hook for future multi-tenant scoping without a schema rewrite.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS edls (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug        text UNIQUE NOT NULL,
  name        text NOT NULL,
  type        text NOT NULL CHECK (type IN ('ip', 'domain', 'url')),
  description text,
  enabled     boolean NOT NULL DEFAULT true,
  owner       text,                       -- reserved for multi-tenant
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  created_by  uuid REFERENCES users(id)
);

-- ----------------------------------------------------------------------------
-- Entries. Soft-disable via `enabled`; time-box via `expires_at` (NULL = never).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS edl_entries (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  edl_id     uuid NOT NULL REFERENCES edls(id) ON DELETE CASCADE,
  value      text NOT NULL,
  comment    text,
  enabled    boolean NOT NULL DEFAULT true,
  expires_at timestamptz,                 -- NULL = never expires
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES users(id),
  UNIQUE (edl_id, value)
);

CREATE INDEX IF NOT EXISTS idx_entries_edl_enabled
  ON edl_entries (edl_id) WHERE enabled;
CREATE INDEX IF NOT EXISTS idx_entries_expires
  ON edl_entries (expires_at) WHERE expires_at IS NOT NULL;

-- ----------------------------------------------------------------------------
-- Audit log: who changed what, with before/after captured in `detail`.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_log (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  actor_sub   text,            -- OIDC sub, or 'system' for the sweeper/import
  actor_email text,
  action      text NOT NULL,   -- create_edl, update_edl, delete_edl,
                               -- add_entry, edit_entry, delete_entry,
                               -- toggle_entry, expire_entry, import
  entity_type text NOT NULL,   -- 'edl' | 'entry'
  entity_id   uuid,
  edl_id      uuid,
  detail      jsonb,           -- { before, after, ... }
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_edl   ON audit_log (edl_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_time  ON audit_log (created_at DESC);

-- ----------------------------------------------------------------------------
-- Fetch log: records firewall pulls of each EDL (observability).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS edl_fetch_log (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  edl_id      uuid REFERENCES edls(id) ON DELETE CASCADE,
  fetched_at  timestamptz NOT NULL DEFAULT now(),
  source_ip   inet,
  user_agent  text,
  entry_count int,
  status      int            -- 200 or 304
);

CREATE INDEX IF NOT EXISTS idx_fetch_edl ON edl_fetch_log (edl_id, fetched_at DESC);

-- ----------------------------------------------------------------------------
-- API tokens for automated writes (e.g. a SOAR/threat-feed script). Stored as a
-- hash only. Not wired to routes yet -- present so it's a non-migrating add.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS api_tokens (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name         text NOT NULL,
  token_hash   text NOT NULL,
  scopes       text[] NOT NULL DEFAULT '{}',
  created_at   timestamptz NOT NULL DEFAULT now(),
  last_used_at timestamptz,
  revoked      boolean NOT NULL DEFAULT false
);

-- ----------------------------------------------------------------------------
-- Session store (connect-pg-simple).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "session" (
  "sid"    varchar NOT NULL COLLATE "default",
  "sess"   json NOT NULL,
  "expire" timestamp(6) NOT NULL
);
ALTER TABLE "session" DROP CONSTRAINT IF EXISTS "session_pkey";
ALTER TABLE "session" ADD CONSTRAINT "session_pkey"
  PRIMARY KEY ("sid") NOT DEFERRABLE INITIALLY IMMEDIATE;
CREATE INDEX IF NOT EXISTS "idx_session_expire" ON "session" ("expire");
