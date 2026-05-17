-- 035_seasons.sql — Seasons: narrative chapters of the transformation journey
-- Pure DDL. No dollar-quoted functions. No CREATE INDEX.

CREATE TABLE IF NOT EXISTS seasons (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    number          INTEGER NOT NULL,
    started_at      DATE NOT NULL,
    ended_at        DATE,
    status          TEXT NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active', 'completed')),
    generated_title TEXT,
    custom_title    TEXT,
    dominant_arc    TEXT CHECK (dominant_arc IN (
                        'rebirth', 'comeback', 'war', 'breakthrough',
                        'ascent', 'foundation', 'plateau', 'descent')),
    personal_note   TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS season_snapshots (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    season_id       UUID REFERENCES seasons(id),
    type            TEXT NOT NULL CHECK (type IN ('start', 'end')),
    captured_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

    weight_lbs      NUMERIC,
    body_fat_pct    NUMERIC,

    phoenix_avg            NUMERIC,
    phoenix_workout_avg    NUMERIC,
    phoenix_stress_avg     NUMERIC,
    phoenix_nutrition_avg  NUMERIC,
    phoenix_resilience_avg NUMERIC,
    phoenix_spirit_avg     NUMERIC,

    pss_score         INTEGER,
    war_room_streak   INTEGER,
    top_prs           JSONB,

    ritual_completion_rate NUMERIC,
    avg_sleep_hrs          NUMERIC,
    avg_calories           NUMERIC,
    avg_protein_g          NUMERIC,

    breathwork_sessions_total  INTEGER,
    meditation_minutes_total   INTEGER,
    journal_entries_total      INTEGER
);

ALTER TABLE seasons          ENABLE ROW LEVEL SECURITY;
ALTER TABLE season_snapshots ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seasons_all          ON seasons;
DROP POLICY IF EXISTS season_snapshots_all ON season_snapshots;

CREATE POLICY seasons_all          ON seasons          FOR ALL TO anon USING (true);
CREATE POLICY season_snapshots_all ON season_snapshots FOR ALL TO anon USING (true);
