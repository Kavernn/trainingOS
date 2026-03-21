-- =============================================================================
-- TrainingOS — Supabase PostgreSQL DDL
-- Run this in the Supabase SQL editor to create the relational schema.
-- Safe to run multiple times (uses CREATE TABLE IF NOT EXISTS).
-- =============================================================================

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";


-- =============================================================================
-- 1. exercises  (replaces "inventory" KV)
-- =============================================================================
-- Computed fields removed:
--   • 1RM is derived on-demand: weight * (1 + reps_max / 30)  [Epley formula]
--   • current_weight is derived from: SELECT weight FROM exercise_logs
--       JOIN workout_sessions ON ... WHERE exercise_id = ? ORDER BY date DESC LIMIT 1
CREATE TABLE IF NOT EXISTS exercises (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT        NOT NULL UNIQUE,
    type            TEXT,                          -- barbell | dumbbell | machine | bodyweight | cable
    category        TEXT,                          -- strength | cardio | hiit | mobility
    pattern         TEXT,                          -- push | pull | hinge | squat | carry | core
    level           TEXT,                          -- beginner | intermediate | advanced
    muscles         TEXT[]      DEFAULT '{}',      -- primary + secondary muscle groups
    tips            TEXT,                          -- coaching cue / technique note
    gif_url         TEXT,
    increment       NUMERIC     DEFAULT 5,         -- kg/lb added when progression triggered
    bar_weight      NUMERIC     DEFAULT 0,         -- tare weight (e.g. 20 for olympic bar)
    default_scheme  TEXT,                          -- e.g. "4x5-7", "3x10-12"
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Index for fast name lookups (also enforced by UNIQUE, but explicit for clarity)
CREATE INDEX IF NOT EXISTS idx_exercises_name ON exercises (name);
CREATE INDEX IF NOT EXISTS idx_exercises_type ON exercises (type);


-- =============================================================================
-- 2. program_sessions  (session definitions: "Upper A", "Lower", etc.)
-- =============================================================================
CREATE TABLE IF NOT EXISTS program_sessions (
    id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT    NOT NULL UNIQUE,
    order_index INT     DEFAULT 0
);


-- =============================================================================
-- 3. program_blocks  (blocks within a session)
-- =============================================================================
CREATE TABLE IF NOT EXISTS program_blocks (
    id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id  UUID    NOT NULL REFERENCES program_sessions (id) ON DELETE CASCADE,
    type        TEXT    NOT NULL CHECK (type IN ('strength', 'hiit', 'cardio')),
    order_index INT     DEFAULT 0,
    hiit_config JSONB   DEFAULT '{}'
    -- cardio_config can be added to hiit_config for now; or add a separate column if needed
);

CREATE INDEX IF NOT EXISTS idx_program_blocks_session ON program_blocks (session_id);


-- =============================================================================
-- 4. program_block_exercises  (exercises assigned to a strength block)
-- =============================================================================
CREATE TABLE IF NOT EXISTS program_block_exercises (
    id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    block_id    UUID    NOT NULL REFERENCES program_blocks (id) ON DELETE CASCADE,
    exercise_id UUID    NOT NULL REFERENCES exercises (id) ON DELETE CASCADE,
    scheme      TEXT,               -- e.g. "4x5-7", "3x10-12"
    order_index INT     DEFAULT 0,
    UNIQUE (block_id, exercise_id)
);

CREATE INDEX IF NOT EXISTS idx_pbe_block      ON program_block_exercises (block_id);
CREATE INDEX IF NOT EXISTS idx_pbe_exercise   ON program_block_exercises (exercise_id);


-- =============================================================================
-- 5. weekly_schedule  (day → session mapping)
-- =============================================================================
-- day_name values: Lun | Mar | Mer | Jeu | Ven | Sam | Dim
CREATE TABLE IF NOT EXISTS weekly_schedule (
    day_name    TEXT    PRIMARY KEY,   -- FR day abbreviation
    session_id  UUID    REFERENCES program_sessions (id) ON DELETE SET NULL
);

-- Seed the 7 days so every day always has a row
INSERT INTO weekly_schedule (day_name) VALUES
    ('Lun'), ('Mar'), ('Mer'), ('Jeu'), ('Ven'), ('Sam'), ('Dim')
ON CONFLICT (day_name) DO NOTHING;


-- =============================================================================
-- 6. workout_sessions  (replaces "sessions" KV)
-- =============================================================================
-- Computed fields removed:
--   • session_volume   → SUM(weight * total_reps_count(reps)) FROM exercise_logs WHERE session_id = ?
--   • total_sets       → COUNT(*) FROM exercise_logs WHERE session_id = ?
--   • total_reps       → SUM(total_reps_count(reps)) FROM exercise_logs WHERE session_id = ?
CREATE TABLE IF NOT EXISTS workout_sessions (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    date            DATE        NOT NULL,
    rpe             SMALLINT    CHECK (rpe BETWEEN 1 AND 10),
    comment         TEXT,
    duration_min    INT,
    energy_pre      INT         CHECK (energy_pre BETWEEN 1 AND 10),
    is_second       BOOLEAN     DEFAULT FALSE,
    logged_at       TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (date, session_type)
);

CREATE INDEX IF NOT EXISTS idx_workout_sessions_date ON workout_sessions (date DESC);


-- =============================================================================
-- 7. exercise_logs  (replaces "weights[exercise].history" KV)
-- =============================================================================
-- Computed fields removed (all derivable from weight + reps):
--   • 1rm          → weight * (1 + max(parse_reps(reps)) / 30)
--   • set_volume   → weight * reps_for_that_set
--   • exercise_volume → weight * SUM(parse_reps(reps))
-- To query 1RM for a given log:
--   SELECT weight * (1 + CAST(split_part(reps, ',', 1) AS NUMERIC) / 30) AS epley_1rm
--   FROM exercise_logs WHERE id = ?
CREATE TABLE IF NOT EXISTS exercise_logs (
    id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id  UUID    NOT NULL REFERENCES workout_sessions (id) ON DELETE CASCADE,
    exercise_id UUID    NOT NULL REFERENCES exercises (id) ON DELETE CASCADE,
    weight      NUMERIC,            -- NULL = bodyweight (volume = 0)
    reps        TEXT,               -- comma-separated per-set reps: "7,6,6,5"
    UNIQUE (session_id, exercise_id)
);

CREATE INDEX IF NOT EXISTS idx_exercise_logs_session   ON exercise_logs (session_id);
CREATE INDEX IF NOT EXISTS idx_exercise_logs_exercise  ON exercise_logs (exercise_id);


-- =============================================================================
-- 8. hiit_logs  (replaces "hiit_log" KV)
-- =============================================================================
CREATE TABLE IF NOT EXISTS hiit_logs (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    date                DATE        NOT NULL,
    session_type        TEXT        NOT NULL,   -- e.g. "HIIT 1", "Sprint"
    rounds_planned      SMALLINT,
    rounds_completed    SMALLINT,
    rpe                 SMALLINT    CHECK (rpe BETWEEN 1 AND 10),
    feeling             TEXT,
    comment             TEXT,
    speed_max           NUMERIC,
    speed_cruise        NUMERIC,
    week                INT,
    is_second           BOOLEAN     DEFAULT FALSE,
    logged_at           TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_hiit_logs_date ON hiit_logs (date DESC);


-- =============================================================================
-- 9. body_weight_logs  (replaces "body_weight" KV)
-- =============================================================================
CREATE TABLE IF NOT EXISTS body_weight_logs (
    id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    date        DATE    NOT NULL UNIQUE,
    weight      NUMERIC NOT NULL,
    note        TEXT    DEFAULT '',
    body_fat    NUMERIC,
    waist_cm    NUMERIC,
    arms_cm     NUMERIC,
    chest_cm    NUMERIC,
    thighs_cm   NUMERIC,
    hips_cm     NUMERIC
);

CREATE INDEX IF NOT EXISTS idx_body_weight_logs_date ON body_weight_logs (date DESC);


-- =============================================================================
-- 10. cardio_logs  (replaces "cardio_log" KV)
-- =============================================================================
CREATE TABLE IF NOT EXISTS cardio_logs (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    date            DATE        NOT NULL,
    type            TEXT        NOT NULL,   -- course | vélo | natation | marche | autre
    duration_min    INT,
    distance_km     NUMERIC,
    avg_hr          NUMERIC,
    avg_pace        TEXT,
    calories        NUMERIC,
    cadence         NUMERIC,
    notes           TEXT,
    source          TEXT        NOT NULL DEFAULT 'manual',  -- manual | healthkit
    rpe             SMALLINT    CHECK (rpe BETWEEN 1 AND 10),
    logged_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cardio_logs_date ON cardio_logs (date DESC);


-- =============================================================================
-- 11. recovery_logs  (replaces "recovery_log" KV)
-- =============================================================================
CREATE TABLE IF NOT EXISTS recovery_logs (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    date            DATE        NOT NULL UNIQUE,
    sleep_hours     NUMERIC,
    sleep_quality   SMALLINT    CHECK (sleep_quality BETWEEN 1 AND 10),
    soreness        SMALLINT    CHECK (soreness BETWEEN 1 AND 10),
    resting_hr      SMALLINT,
    hrv             NUMERIC,
    steps           INT,
    active_energy   NUMERIC,    -- kcal actives (Apple Watch)
    source          TEXT        NOT NULL DEFAULT 'manual',  -- manual | healthkit
    notes           TEXT
);

CREATE INDEX IF NOT EXISTS idx_recovery_logs_date ON recovery_logs (date DESC);


-- =============================================================================
-- 12. goals  (replaces "goals" KV)
-- =============================================================================
-- Computed fields removed:
--   • achieved → derived by comparing target_weight with latest exercise_logs.weight
--     Query: SELECT weight >= g.target_weight AS achieved
--            FROM exercise_logs el JOIN workout_sessions ws ON ws.id = el.session_id
--            JOIN goals g ON g.exercise_id = el.exercise_id
--            WHERE el.exercise_id = ? ORDER BY ws.date DESC LIMIT 1
--   • current_weight → see v_exercise_current view
CREATE TABLE IF NOT EXISTS goals (
    id              UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    exercise_id     UUID    NOT NULL REFERENCES exercises (id) ON DELETE CASCADE,
    target_weight   NUMERIC NOT NULL,
    target_date     DATE,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (exercise_id)
);

CREATE INDEX IF NOT EXISTS idx_goals_exercise ON goals (exercise_id);


-- =============================================================================
-- 13. nutrition_settings  (single-row)
-- =============================================================================
CREATE TABLE IF NOT EXISTS nutrition_settings (
    id              INT     PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    calorie_limit   INT     DEFAULT 2000,
    protein_target  INT     DEFAULT 150,
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO nutrition_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;


-- =============================================================================
-- 14. nutrition_logs  (replaces "nutrition_log" KV)
-- =============================================================================
CREATE TABLE IF NOT EXISTS nutrition_logs (
    id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    date        DATE    NOT NULL,
    meal        TEXT,               -- breakfast | lunch | dinner | snack
    food        TEXT    NOT NULL,
    calories    INT,
    protein     NUMERIC,
    carbs       NUMERIC,
    fat         NUMERIC,
    logged_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_nutrition_logs_date ON nutrition_logs (date DESC);


-- =============================================================================
-- 15. mood_logs  (replaces "mood_log" KV)
-- =============================================================================
CREATE TABLE IF NOT EXISTS mood_logs (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    date                DATE        NOT NULL,
    score               SMALLINT    CHECK (score BETWEEN 1 AND 10),
    emotions            TEXT[]      DEFAULT '{}',
    triggers            TEXT[]      DEFAULT '{}',
    notes               TEXT,
    pss_score_linked    INT
);

CREATE INDEX IF NOT EXISTS idx_mood_logs_date ON mood_logs (date DESC);


-- =============================================================================
-- 16. pss_records  (replaces "pss_records" KV)
--     PSS = Perceived Stress Scale
-- =============================================================================
CREATE TABLE IF NOT EXISTS pss_records (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    date                DATE        NOT NULL,
    type                TEXT        DEFAULT 'full',   -- full | short
    score               SMALLINT,
    max_score           SMALLINT    DEFAULT 40,
    category            TEXT,                          -- low | moderate | high
    category_label      TEXT,
    streak              INT,
    responses           SMALLINT[],
    inverted_responses  SMALLINT[],
    triggers            TEXT[]      DEFAULT '{}',
    trigger_ratings     JSONB       DEFAULT '{}',
    insights            TEXT[]      DEFAULT '{}',
    notes               TEXT,
    recorded_at         TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pss_records_date ON pss_records (date DESC);


-- =============================================================================
-- 17. self_care_habits  (replaces "self_care_habits" KV)
-- =============================================================================
CREATE TABLE IF NOT EXISTS self_care_habits (
    id          TEXT    PRIMARY KEY,   -- e.g. "walk", "meditate", "read"
    name        TEXT    NOT NULL,
    icon        TEXT,
    category    TEXT,
    is_default  BOOLEAN DEFAULT FALSE,
    order_index INT     DEFAULT 0
);


-- =============================================================================
-- 18. self_care_logs  (replaces "self_care_log" KV)
-- =============================================================================
CREATE TABLE IF NOT EXISTS self_care_logs (
    id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    date        DATE    NOT NULL,
    habit_id    TEXT    NOT NULL REFERENCES self_care_habits (id) ON DELETE CASCADE,
    UNIQUE (date, habit_id)
);

CREATE INDEX IF NOT EXISTS idx_self_care_logs_date ON self_care_logs (date DESC);


-- =============================================================================
-- 19. life_stress_scores  (replaces "life_stress_scores" KV)
-- =============================================================================
CREATE TABLE IF NOT EXISTS life_stress_scores (
    id              UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    date            DATE    NOT NULL UNIQUE,
    score           NUMERIC,
    data_coverage   NUMERIC,
    flags           JSONB   DEFAULT '{}',
    components      JSONB   DEFAULT '{}',
    recommendations TEXT[]  DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_life_stress_scores_date ON life_stress_scores (date DESC);


-- =============================================================================
-- 20. journal_entries  (replaces "journal_entries" KV)
-- =============================================================================
CREATE TABLE IF NOT EXISTS journal_entries (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    date        DATE        NOT NULL,
    content     TEXT        NOT NULL,
    mood_score  SMALLINT    CHECK (mood_score BETWEEN 1 AND 10),
    tags        TEXT[]      DEFAULT '{}',
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_journal_entries_date ON journal_entries (date DESC);


-- =============================================================================
-- 21. breathwork_sessions  (replaces "breathwork_sessions" KV)
-- =============================================================================
CREATE TABLE IF NOT EXISTS breathwork_sessions (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    date            DATE        NOT NULL,
    technique       TEXT,                   -- box | 4-7-8 | wim_hof | coherence | etc.
    duration_min    INT,
    notes           TEXT,
    logged_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_breathwork_sessions_date ON breathwork_sessions (date DESC);


-- =============================================================================
-- 22. sleep_records  (replaces "sleep_records" KV)
-- =============================================================================
CREATE TABLE IF NOT EXISTS sleep_records (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    date            DATE        NOT NULL,
    duration_hours  NUMERIC,
    quality         SMALLINT    CHECK (quality BETWEEN 1 AND 10),
    notes           TEXT,
    logged_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sleep_records_date ON sleep_records (date DESC);


-- =============================================================================
-- 23. coach_history  (replaces "coach_history" KV)
-- =============================================================================
CREATE TABLE IF NOT EXISTS coach_history (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    mode                TEXT,                   -- coach | analyst | planner | etc.
    user_message        TEXT,
    assistant_response  TEXT
);

CREATE INDEX IF NOT EXISTS idx_coach_history_created ON coach_history (created_at DESC);


-- =============================================================================
-- 24. user_profile  (single-row)
-- =============================================================================
CREATE TABLE IF NOT EXISTS user_profile (
    id          INT     PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    name        TEXT,
    age         SMALLINT,
    sex         CHAR(1) CHECK (sex IN ('M', 'F')),
    weight      NUMERIC,           -- current body weight (informational, NOT synced from body_weight_logs)
    height      SMALLINT,          -- cm
    level       TEXT,              -- beginner | intermediate | advanced
    goal        TEXT,              -- bulk | cut | maintain | recomp
    units       TEXT    DEFAULT 'kg',
    photo_b64   TEXT,
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO user_profile (id) VALUES (1) ON CONFLICT (id) DO NOTHING;


-- =============================================================================
-- 25. deload_state  (single-row)
-- =============================================================================
CREATE TABLE IF NOT EXISTS deload_state (
    id          INT     PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    active      BOOLEAN DEFAULT FALSE,
    started_at  DATE,
    reason      TEXT
);

INSERT INTO deload_state (id) VALUES (1) ON CONFLICT (id) DO NOTHING;


-- =============================================================================
-- ANALYTICAL VIEWS
-- =============================================================================

-- v_exercise_current
-- Returns the most recent logged weight, reps, and session count per exercise.
-- Use this to answer "what is the current working weight for Bench Press?"
-- 1RM computation: weight * (1 + max_set_reps / 30)  where max_set_reps = max of parse(reps)
CREATE OR REPLACE VIEW v_exercise_current AS
SELECT
    e.id                                            AS exercise_id,
    e.name                                          AS exercise_name,
    e.type,
    latest.weight                                   AS latest_weight,
    latest.reps                                     AS latest_reps,
    session_counts.session_count,
    -- Epley 1RM estimate (best-set, using first value in reps string as proxy for top set)
    CASE
        WHEN latest.weight IS NOT NULL AND latest.weight > 0
        THEN ROUND(
            latest.weight * (
                1 + GREATEST(
                    COALESCE(
                        (SELECT MAX(r::INT)
                         FROM unnest(string_to_array(latest.reps, ',')) AS r
                         WHERE r ~ '^\d+$'),
                        1
                    )::NUMERIC / 30
                )
            ), 1)
        ELSE NULL
    END                                             AS epley_1rm
FROM exercises e
LEFT JOIN LATERAL (
    SELECT el.weight, el.reps
    FROM exercise_logs el
    JOIN workout_sessions ws ON ws.id = el.session_id
    WHERE el.exercise_id = e.id
    ORDER BY ws.date DESC
    LIMIT 1
) latest ON TRUE
LEFT JOIN (
    SELECT exercise_id, COUNT(*) AS session_count
    FROM exercise_logs
    GROUP BY exercise_id
) session_counts ON session_counts.exercise_id = e.id;


-- v_session_volume
-- Returns computed volume metrics per workout session.
-- volume     = SUM(weight * total_reps_for_exercise)
-- total_sets = COUNT(exercise_logs rows)  — one row per exercise per session
-- total_reps = SUM of all individual set reps across all exercises
-- Note: bodyweight exercises (weight IS NULL or 0) contribute 0 to volume.
CREATE OR REPLACE VIEW v_session_volume AS
SELECT
    ws.id                                               AS session_id,
    ws.date,
    ws.rpe,
    ws.duration_min,
    ROUND(SUM(
        COALESCE(el.weight, 0) * COALESCE((
            SELECT SUM(r::INT)
            FROM unnest(string_to_array(el.reps, ',')) AS r
            WHERE r ~ '^\d+$'
        ), 0)
    ), 2)                                               AS total_volume,
    COUNT(el.id)                                        AS total_sets,
    SUM(COALESCE((
        SELECT SUM(r::INT)
        FROM unnest(string_to_array(el.reps, ',')) AS r
        WHERE r ~ '^\d+$'
    ), 0))                                              AS total_reps
FROM workout_sessions ws
LEFT JOIN exercise_logs el ON el.session_id = ws.id
GROUP BY ws.id, ws.date, ws.rpe, ws.duration_min;


-- v_weekly_volume
-- Aggregates session volume by ISO calendar week.
-- Useful for weekly load monitoring and overtraining detection.
CREATE OR REPLACE VIEW v_weekly_volume AS
SELECT
    DATE_TRUNC('week', ws.date)                     AS week_start,
    EXTRACT(WEEK FROM ws.date)::INT                 AS week_number,
    EXTRACT(YEAR FROM ws.date)::INT                 AS year,
    ROUND(SUM(
        COALESCE(el.weight, 0) * COALESCE((
            SELECT SUM(r::INT)
            FROM unnest(string_to_array(el.reps, ',')) AS r
            WHERE r ~ '^\d+$'
        ), 0)
    ), 2)                                           AS total_volume,
    COUNT(DISTINCT ws.id)                           AS session_count,
    COUNT(el.id)                                    AS total_sets
FROM workout_sessions ws
LEFT JOIN exercise_logs el ON el.session_id = ws.id
GROUP BY DATE_TRUNC('week', ws.date), EXTRACT(WEEK FROM ws.date), EXTRACT(YEAR FROM ws.date)
ORDER BY week_start DESC;


-- =============================================================================
-- MIGRATION 001 — Apple Watch / HealthKit columns (2026-03-20)
-- Run this in Supabase SQL Editor on existing databases.
-- Safe to run multiple times (IF NOT EXISTS / IF NOT EXISTS guards).
-- =============================================================================

-- cardio_logs: add wearable columns
ALTER TABLE cardio_logs ADD COLUMN IF NOT EXISTS avg_hr      NUMERIC;
ALTER TABLE cardio_logs ADD COLUMN IF NOT EXISTS avg_pace    TEXT;
ALTER TABLE cardio_logs ADD COLUMN IF NOT EXISTS calories    NUMERIC;
ALTER TABLE cardio_logs ADD COLUMN IF NOT EXISTS cadence     NUMERIC;
ALTER TABLE cardio_logs ADD COLUMN IF NOT EXISTS notes       TEXT;
ALTER TABLE cardio_logs ADD COLUMN IF NOT EXISTS source      TEXT NOT NULL DEFAULT 'manual';

-- recovery_logs: add wearable columns
ALTER TABLE recovery_logs ADD COLUMN IF NOT EXISTS active_energy  NUMERIC;
ALTER TABLE recovery_logs ADD COLUMN IF NOT EXISTS source         TEXT NOT NULL DEFAULT 'manual';

-- exercises: tracking_type for time-based exercises (e.g. Plank)
-- Values: 'reps' (default) | 'time' (duration in seconds, no weight)
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS tracking_type TEXT NOT NULL DEFAULT 'reps';
-- To mark an exercise as time-based:
-- UPDATE exercises SET tracking_type = 'time' WHERE name IN ('Plank', 'Dead Hang', 'Wall Sit');

-- =============================================================================
-- MIGRATION 002 — RLS + anon policies (2026-03-21)
-- Le backend utilise SUPABASE_ANON_KEY. RLS doit être activé sur toutes les
-- tables avec une policy anon permissive (accès total) — cohérent avec le
-- fait que c'est une app privée mono-utilisateur derrière un backend Flask.
--
-- RÈGLE : chaque nouvelle table créée doit avoir ces 2 lignes associées :
--   ALTER TABLE public.<table> ENABLE ROW LEVEL SECURITY;
--   CREATE POLICY "anon_all" ON public.<table> FOR ALL TO anon USING (true) WITH CHECK (true);
-- =============================================================================

ALTER TABLE public.exercises              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.program_sessions       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.program_blocks         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.program_block_exercises ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.weekly_schedule        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workout_sessions       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exercise_logs          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hiit_logs              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.body_weight_logs       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cardio_logs            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recovery_logs          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.goals                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nutrition_settings     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nutrition_logs         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mood_logs              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pss_records            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.self_care_habits       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.self_care_logs         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.life_stress_scores     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.journal_entries        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.breathwork_sessions    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sleep_records          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_history          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_profile           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deload_state           ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'exercises','program_sessions','program_blocks','program_block_exercises',
    'weekly_schedule','workout_sessions','exercise_logs','hiit_logs',
    'body_weight_logs','cardio_logs','recovery_logs','goals',
    'nutrition_settings','nutrition_logs','mood_logs','pss_records',
    'self_care_habits','self_care_logs','life_stress_scores','journal_entries',
    'breathwork_sessions','sleep_records','coach_history','user_profile','deload_state'
  ] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = t AND policyname = 'anon_all'
    ) THEN
      EXECUTE format('CREATE POLICY anon_all ON public.%I FOR ALL TO anon USING (true) WITH CHECK (true)', t);
    END IF;
  END LOOP;
END $$;
