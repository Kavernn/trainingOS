-- Migration 027: Time Capsule table
-- Run in Supabase SQL Editor before deploying the time capsule feature.

CREATE TABLE IF NOT EXISTS time_capsules (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    unlock_at        TIMESTAMPTZ NOT NULL,
    unlocked_at      TIMESTAMPTZ,
    duration_months  INTEGER NOT NULL CHECK (duration_months IN (1, 3, 6)),
    message          TEXT,
    snapshot         JSONB NOT NULL DEFAULT '{}',
    is_opened        BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_time_capsules_unlock_at  ON time_capsules (unlock_at);
CREATE INDEX IF NOT EXISTS idx_time_capsules_is_opened  ON time_capsules (is_opened);
