-- Migration 004 — Daily Ritual
-- Run in Supabase SQL Editor before deploying the ritual feature.

CREATE TABLE IF NOT EXISTS daily_ritual (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    date         DATE        NOT NULL UNIQUE,
    truth        TEXT        NOT NULL DEFAULT '',
    truth_type   TEXT        NOT NULL DEFAULT 'default',
    intention    TEXT,
    morning_at   TIMESTAMPTZ,
    outcome      TEXT        CHECK (outcome IN ('burned', 'survived')),
    evening_at   TIMESTAMPTZ,
    carried_from DATE,
    carry_count  INT         NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_daily_ritual_date ON daily_ritual (date DESC);

-- RLS: same pattern as other single-user tables (allow all for authenticated)
ALTER TABLE daily_ritual ENABLE ROW LEVEL SECURITY;

CREATE POLICY "allow_all" ON daily_ritual
    FOR ALL USING (true) WITH CHECK (true);
