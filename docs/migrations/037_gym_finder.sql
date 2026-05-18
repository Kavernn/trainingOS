-- Migration 037: Gym Finder crowdsource tables
-- Run in Supabase SQL Editor

-- Crowdsource contributions (anonymous — no user_id)
CREATE TABLE IF NOT EXISTS gym_contributions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id          TEXT NOT NULL,
    gym_name        TEXT,
    latitude        DOUBLE PRECISION,
    longitude       DOUBLE PRECISION,
    drop_in_price   NUMERIC(7, 2),
    equipment       TEXT[] DEFAULT '{}',
    vibe_hardcore   SMALLINT CHECK (vibe_hardcore BETWEEN 1 AND 5),
    vibe_crowded    SMALLINT CHECK (vibe_crowded BETWEEN 1 AND 5),
    vibe_music      SMALLINT CHECK (vibe_music BETWEEN 1 AND 5),
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_gym_contributions_gym_id ON gym_contributions (gym_id);

-- Gym visit history (per user)
CREATE TABLE IF NOT EXISTS user_gym_history (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id      TEXT NOT NULL,
    gym_name    TEXT,
    latitude    DOUBLE PRECISION,
    longitude   DOUBLE PRECISION,
    visited_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_gym_history_visited ON user_gym_history (visited_at DESC);

-- RLS: contributions are write-only from client, readable by service role
ALTER TABLE gym_contributions ENABLE ROW LEVEL SECURITY;
CREATE POLICY IF NOT EXISTS "gym_contributions_insert" ON gym_contributions
    FOR INSERT WITH CHECK (true);

ALTER TABLE user_gym_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY IF NOT EXISTS "user_gym_history_insert" ON user_gym_history
    FOR INSERT WITH CHECK (true);
CREATE POLICY IF NOT EXISTS "user_gym_history_select" ON user_gym_history
    FOR SELECT USING (true);
