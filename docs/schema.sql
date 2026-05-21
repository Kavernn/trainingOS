-- =============================================================================
-- TrainingOS — Supabase PostgreSQL DDL
-- SOURCE DE VÉRITÉ UNIQUE — incorpore migrations 001 à 047.
-- ⚠️  Ne pas modifier manuellement. Refléter tout changement dans une migration.
-- Safe à exécuter plusieurs fois (CREATE TABLE IF NOT EXISTS + ON CONFLICT).
-- =============================================================================

-- Extension UUID
CREATE EXTENSION IF NOT EXISTS "pgcrypto";


-- =============================================================================
-- === Tier 1 : Référentiel ===
-- =============================================================================

-- === 1. programs ===
-- Créée par migration 002 — table mère des programmes d'entraînement
CREATE TABLE IF NOT EXISTS programs (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT        NOT NULL UNIQUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.programs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.programs FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 2. exercises ===
-- Référentiel des exercices — avec tracking_type (migration 001) + soft delete (migration 020)
CREATE TABLE IF NOT EXISTS exercises (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT        NOT NULL UNIQUE,
    type            TEXT,                              -- barbell | dumbbell | machine | bodyweight | cable
    category        TEXT,                              -- strength | cardio | hiit | mobility
    pattern         TEXT,                              -- push | pull | hinge | squat | carry | core
    level           TEXT,                              -- beginner | intermediate | advanced
    muscles         TEXT[]      DEFAULT '{}',          -- groupes musculaires primaires + secondaires
    tips            TEXT,                              -- cue technique / note de coaching
    gif_url         TEXT,
    increment       NUMERIC     DEFAULT 5,             -- kg/lb ajoutés lors d'une progression
    bar_weight      NUMERIC     DEFAULT 0,             -- poids de la barre (ex. 20 pour barre olympique)
    default_scheme  TEXT,                              -- ex. "4x5-7", "3x10-12"
    tracking_type   TEXT        NOT NULL DEFAULT 'reps',  -- reps | time (migration 001)
    current_weight  NUMERIC,                           -- poids courant suggéré (migration 011)
    deleted_at      TIMESTAMPTZ,                       -- soft delete (migration 020)
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_exercises_name ON exercises (name);
CREATE INDEX IF NOT EXISTS idx_exercises_type ON exercises (type);

ALTER TABLE public.exercises ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.exercises FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 3. program_sessions ===
-- Sessions de programme — liées à un programme (migration 002 : program_id NOT NULL)
CREATE TABLE IF NOT EXISTS program_sessions (
    id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    program_id  UUID    NOT NULL REFERENCES programs(id) ON DELETE CASCADE,
    name        TEXT    NOT NULL,
    order_index INT     DEFAULT 0
);

-- Index unique par programme (remplace l'ancien UNIQUE(name) global — migration 002)
CREATE UNIQUE INDEX IF NOT EXISTS idx_program_sessions_program_name
    ON program_sessions (program_id, name);

ALTER TABLE public.program_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.program_sessions FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 4. program_blocks ===
-- Blocs dans une session (force | hiit | cardio)
CREATE TABLE IF NOT EXISTS program_blocks (
    id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id  UUID    NOT NULL REFERENCES program_sessions(id) ON DELETE CASCADE,
    type        TEXT    NOT NULL CHECK (type IN ('strength', 'hiit', 'cardio')),
    order_index INT     DEFAULT 0,
    hiit_config JSONB   DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_program_blocks_session ON program_blocks (session_id);

ALTER TABLE public.program_blocks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.program_blocks FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 5. program_block_exercises ===
-- Exercices assignés à un bloc de force
CREATE TABLE IF NOT EXISTS program_block_exercises (
    id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    block_id    UUID    NOT NULL REFERENCES program_blocks(id) ON DELETE CASCADE,
    exercise_id UUID    NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
    scheme      TEXT,               -- ex. "4x5-7", "3x10-12"
    order_index INT     DEFAULT 0,
    UNIQUE (block_id, exercise_id)
);

CREATE INDEX IF NOT EXISTS idx_pbe_block    ON program_block_exercises (block_id);
CREATE INDEX IF NOT EXISTS idx_pbe_exercise ON program_block_exercises (exercise_id);

ALTER TABLE public.program_block_exercises ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.program_block_exercises FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 6. weekly_schedule ===
-- Mapping jour → session, PK composite (day_name, slot) — migration 002
-- day_name : Lun | Mar | Mer | Jeu | Ven | Sam | Dim
-- slot     : morning | evening
CREATE TABLE IF NOT EXISTS weekly_schedule (
    day_name    TEXT    NOT NULL,
    slot        TEXT    NOT NULL DEFAULT 'morning',
    session_id  UUID    REFERENCES program_sessions(id) ON DELETE SET NULL,
    PRIMARY KEY (day_name, slot)
);

-- Seed des 7 jours (slot morning) — toujours présents
INSERT INTO weekly_schedule (day_name, slot) VALUES
    ('Lun', 'morning'), ('Mar', 'morning'), ('Mer', 'morning'),
    ('Jeu', 'morning'), ('Ven', 'morning'), ('Sam', 'morning'), ('Dim', 'morning')
ON CONFLICT DO NOTHING;

ALTER TABLE public.weekly_schedule ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.weekly_schedule FOR ALL TO anon USING (true) WITH CHECK (true);


-- =============================================================================
-- === Tier 2 : Entraînement ===
-- =============================================================================

-- === 7. workout_sessions ===
-- Séances d'entraînement réalisées
CREATE TABLE IF NOT EXISTS workout_sessions (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    date            DATE        NOT NULL,
    rpe             NUMERIC(4,1) CHECK (rpe BETWEEN 1 AND 10),
    comment         TEXT,
    duration_min    INT,
    energy_pre      INT         CHECK (energy_pre BETWEEN 1 AND 10),
    session_name    TEXT        NOT NULL DEFAULT 'Séance',  -- ex. "Push A", "Pull B" (migration 046)
    is_second       BOOLEAN     DEFAULT FALSE,
    session_type    TEXT        NOT NULL DEFAULT 'morning',
    completed       BOOLEAN     NOT NULL DEFAULT FALSE,
    logged_at       TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (date, session_type)
);

CREATE INDEX IF NOT EXISTS idx_workout_sessions_date ON workout_sessions (date DESC);

ALTER TABLE public.workout_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.workout_sessions FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 8. exercise_logs ===
-- Logs par exercice par séance, avec RPE et zone de douleur (migration 024)
-- 1RM calculé à la volée : Epley ≤10 reps, Brzycki 11-20 reps, NULL >20 reps
CREATE TABLE IF NOT EXISTS exercise_logs (
    id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id  UUID    NOT NULL REFERENCES workout_sessions(id) ON DELETE CASCADE,
    exercise_id UUID    NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
    weight      NUMERIC,            -- NULL = poids de corps ; unité selon UnitSettings
    reps        TEXT,               -- reps par set séparés par virgule : "7,6,6,5"
    sets_json   JSONB   DEFAULT '[]'::jsonb,  -- [{weight, reps, total_weight, set_volume}]
    rpe         NUMERIC(4,1) CHECK (rpe BETWEEN 1 AND 10),  -- migration 024
    pain_zone   TEXT,                                        -- migration 024
    UNIQUE (session_id, exercise_id)
);

CREATE INDEX IF NOT EXISTS idx_exercise_logs_session  ON exercise_logs (session_id);
CREATE INDEX IF NOT EXISTS idx_exercise_logs_exercise ON exercise_logs (exercise_id);

ALTER TABLE public.exercise_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.exercise_logs FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 9. hiit_logs ===
-- Séances HIIT
CREATE TABLE IF NOT EXISTS hiit_logs (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    date                DATE        NOT NULL,
    session_type        TEXT        NOT NULL,   -- ex. "HIIT 1", "Sprint"
    rounds_planned      SMALLINT,
    rounds_completed    SMALLINT,
    rpe                 NUMERIC(4,1) CHECK (rpe BETWEEN 1 AND 10),
    feeling             TEXT,
    comment             TEXT,
    speed_max           NUMERIC,
    speed_cruise        NUMERIC,
    week                INT,
    is_second           BOOLEAN     DEFAULT FALSE,
    logged_at           TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_hiit_logs_date ON hiit_logs (date DESC);

ALTER TABLE public.hiit_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.hiit_logs FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 10. goals ===
-- Objectifs de performance liés à un exercice
CREATE TABLE IF NOT EXISTS goals (
    id              UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    exercise_id     UUID    NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
    target_weight   NUMERIC NOT NULL,
    target_date     DATE,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (exercise_id)
);

CREATE INDEX IF NOT EXISTS idx_goals_exercise ON goals (exercise_id);

ALTER TABLE public.goals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.goals FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 11. goals_archived ===
-- Objectifs archivés (migration 011)
CREATE TABLE IF NOT EXISTS goals_archived (
    id            UUID  PRIMARY KEY DEFAULT gen_random_uuid(),
    exercise_name TEXT  NOT NULL UNIQUE
);

ALTER TABLE public.goals_archived ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.goals_archived FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 12. generated_programs ===
-- Programmes générés par l'IA en attente d'approbation (migration 014)
CREATE TABLE IF NOT EXISTS generated_programs (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    generated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status        TEXT        NOT NULL DEFAULT 'pending_approval',
    -- 'pending_approval' | 'active' | 'archived'
    program_json  JSONB       NOT NULL,
    programme_id  UUID,                               -- défini après approbation → programs.id
    notes         TEXT
);

ALTER TABLE public.generated_programs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.generated_programs FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 13. plateau_alerts ===
-- Alertes de plateau détectées par l'IA (migration 028)
CREATE TABLE IF NOT EXISTS plateau_alerts (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    detected_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    exercise_name    TEXT        NOT NULL,
    plateau_score    INTEGER     NOT NULL,
    plateau_weeks    INTEGER     NOT NULL,
    root_cause       TEXT        NOT NULL,
    severity         TEXT        NOT NULL CHECK (severity IN ('advisory', 'warning', 'critical')),
    deload_type      TEXT        CHECK (deload_type IN ('rest', 'light_week', 'rep_range', 'nutrition_first')),
    deload_plan      JSONB,
    rebound_days_min INTEGER,
    rebound_days_max INTEGER,
    status           TEXT        NOT NULL DEFAULT 'pending'
                                 CHECK (status IN ('pending', 'accepted', 'active', 'completed', 'dismissed')),
    dismissed_at     TIMESTAMPTZ,
    completed_at     TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_plateau_alerts_exercise ON plateau_alerts (exercise_name);
CREATE INDEX IF NOT EXISTS idx_plateau_alerts_status   ON plateau_alerts (status);
CREATE INDEX IF NOT EXISTS idx_plateau_alerts_detected ON plateau_alerts (detected_at DESC);

ALTER TABLE public.plateau_alerts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.plateau_alerts FOR ALL TO anon USING (true) WITH CHECK (true);


-- =============================================================================
-- === Tier 3 : Biométrie ===
-- =============================================================================

-- === 14. body_weight_logs ===
-- Pesées quotidiennes, avec mesures corporelles + neck_cm (migration 029)
CREATE TABLE IF NOT EXISTS body_weight_logs (
    id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    date        DATE    NOT NULL UNIQUE,
    weight      NUMERIC NOT NULL,    -- unité : lbs
    note        TEXT    DEFAULT '',
    body_fat    NUMERIC,
    waist_cm    NUMERIC,
    neck_cm     NUMERIC,             -- migration 029
    arms_cm     NUMERIC,
    chest_cm    NUMERIC,
    thighs_cm   NUMERIC,
    hips_cm     NUMERIC
);

CREATE INDEX IF NOT EXISTS idx_body_weight_logs_date ON body_weight_logs (date DESC);

ALTER TABLE public.body_weight_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.body_weight_logs FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 15. cardio_logs ===
-- Séances cardio — colonnes HealthKit intégrées (migration 001 inline)
CREATE TABLE IF NOT EXISTS cardio_logs (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    date            DATE        NOT NULL,
    type            TEXT        NOT NULL,   -- course | vélo | natation | marche | autre
    duration_min    INT,
    distance_km     NUMERIC,
    avg_hr          NUMERIC,               -- migration 001
    avg_pace        TEXT,                  -- migration 001
    calories        NUMERIC,               -- migration 001
    cadence         NUMERIC,               -- migration 001
    notes           TEXT,                  -- migration 001
    source          TEXT        NOT NULL DEFAULT 'manual',  -- manual | healthkit (migration 001)
    rpe             NUMERIC(4,1) CHECK (rpe BETWEEN 1 AND 10),
    logged_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cardio_logs_date ON cardio_logs (date DESC);

ALTER TABLE public.cardio_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.cardio_logs FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 16. recovery_logs ===
-- Récupération quotidienne — colonnes HealthKit (migration 001) + HR moments (migration 017) + fatigue Hooper (migration 038)
CREATE TABLE IF NOT EXISTS recovery_logs (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    date                DATE        NOT NULL UNIQUE,
    sleep_hours         NUMERIC,
    sleep_quality       SMALLINT    CHECK (sleep_quality BETWEEN 1 AND 10),
    soreness            SMALLINT    CHECK (soreness BETWEEN 1 AND 10),
    resting_hr          SMALLINT,
    hrv                 NUMERIC,
    steps               INT,
    active_energy       NUMERIC,    -- kcal actives Apple Watch (migration 001)
    hr_morning          SMALLINT,   -- FC matin 06-09h (migration 017)
    hr_post_workout     SMALLINT,   -- FC post-séance +30 min (migration 017)
    hr_evening          SMALLINT,   -- FC soir 21-23h (migration 017)
    fatigue_perceived   SMALLINT,   -- Hooper Index fatigue perçue 0-10 (migration 038)
    source              TEXT        NOT NULL DEFAULT 'manual',  -- manual | healthkit (migration 001)
    notes               TEXT
);

CREATE INDEX IF NOT EXISTS idx_recovery_logs_date ON recovery_logs (date DESC);

ALTER TABLE public.recovery_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.recovery_logs FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 17. hydration_logs ===
-- Suivi hydrique (migration 039) — objectif 35 ml × poids_kg + 600 ml si séance
CREATE TABLE IF NOT EXISTS hydration_logs (
    id          UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
    date        DATE        NOT NULL DEFAULT CURRENT_DATE,
    logged_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    amount_ml   INTEGER     NOT NULL CHECK (amount_ml > 0)
);

CREATE INDEX IF NOT EXISTS hydration_logs_date_idx ON hydration_logs (date);

ALTER TABLE public.hydration_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.hydration_logs FOR ALL TO anon USING (true) WITH CHECK (true);


-- =============================================================================
-- === Tier 4 : Nutrition ===
-- =============================================================================

-- === 18. nutrition_settings ===
-- Paramètres nutritionnels — table single-row
CREATE TABLE IF NOT EXISTS nutrition_settings (
    id              INT     PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    calorie_limit   INT     DEFAULT 2000,
    protein_target  INT     DEFAULT 150,
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO nutrition_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.nutrition_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.nutrition_settings FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 19. nutrition_logs ===
-- Journal nutritionnel (format legacy par repas)
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

ALTER TABLE public.nutrition_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.nutrition_logs FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 20. meal_templates ===
-- Templates de repas réutilisables (migration 018)
CREATE TABLE IF NOT EXISTS meal_templates (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT        NOT NULL,
    items       JSONB       NOT NULL DEFAULT '[]',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.meal_templates ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.meal_templates FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 21. food_catalog ===
-- Catalogue d'aliments personnalisé (migration 004_food_catalog)
CREATE TABLE IF NOT EXISTS food_catalog (
    id          TEXT    PRIMARY KEY,
    name        TEXT    NOT NULL,
    ref_qty     REAL    NOT NULL DEFAULT 100,
    ref_unit    TEXT    NOT NULL DEFAULT 'g',
    calories    REAL    NOT NULL DEFAULT 0,
    proteines   REAL    NOT NULL DEFAULT 0,
    glucides    REAL    NOT NULL DEFAULT 0,
    lipides     REAL    NOT NULL DEFAULT 0
);

ALTER TABLE public.food_catalog ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.food_catalog FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 22. nutrition_entries ===
-- Entrées nutritionnelles individuelles (migration nutrition_entries)
CREATE TABLE IF NOT EXISTS nutrition_entries (
    id          TEXT        PRIMARY KEY,          -- UUID court 8 chars généré par l'app
    date        DATE        NOT NULL,
    nom         TEXT        NOT NULL,
    calories    INTEGER     NOT NULL DEFAULT 0,
    proteines   REAL        NOT NULL DEFAULT 0,
    glucides    REAL        NOT NULL DEFAULT 0,
    lipides     REAL        NOT NULL DEFAULT 0,
    heure       TEXT,                             -- HH:MM défini à l'insertion
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS nutrition_entries_date_idx ON nutrition_entries (date DESC);

ALTER TABLE public.nutrition_entries ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.nutrition_entries FOR ALL TO anon USING (true) WITH CHECK (true);


-- =============================================================================
-- === Tier 5 : Santé mentale ===
-- =============================================================================

-- === 23. pss_records ===
-- Enregistrements PSS (Perceived Stress Scale) — déclaré avant mood_logs (FK)
CREATE TABLE IF NOT EXISTS pss_records (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    date                DATE        NOT NULL,
    type                TEXT        NOT NULL DEFAULT 'full',  -- full | short (migration 046)
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

ALTER TABLE public.pss_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.pss_records FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 24. mood_logs ===
-- Journaux d'humeur — avec FK formelle vers pss_records (migration 044)
CREATE TABLE IF NOT EXISTS mood_logs (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    date                DATE        NOT NULL,
    score               SMALLINT    CHECK (score BETWEEN 1 AND 10),
    emotions            TEXT[]      DEFAULT '{}',
    triggers            TEXT[]      DEFAULT '{}',
    notes               TEXT,
    pss_score_linked    INT,                           -- score PSS dénormalisé (rétrocompatibilité)
    pss_record_id       UUID        REFERENCES pss_records(id) ON DELETE SET NULL  -- migration 044
);

CREATE INDEX IF NOT EXISTS idx_mood_logs_date ON mood_logs (date DESC);

ALTER TABLE public.mood_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.mood_logs FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 25. journal_entries ===
-- Journal personnel — avec colonne prompt (migration 011)
CREATE TABLE IF NOT EXISTS journal_entries (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    date        DATE        NOT NULL,
    content     TEXT        NOT NULL,
    mood_score  SMALLINT    CHECK (mood_score BETWEEN 1 AND 10),
    tags        TEXT[]      DEFAULT '{}',
    prompt      TEXT,                                  -- question guidée du jour (migration 011)
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_journal_entries_date ON journal_entries (date DESC);

ALTER TABLE public.journal_entries ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.journal_entries FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 26. life_stress_scores ===
-- Scores de stress composite calculés
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

ALTER TABLE public.life_stress_scores ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.life_stress_scores FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 27. daily_ritual ===
-- Rituel quotidien matin/soir (migration 004)
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

ALTER TABLE public.daily_ritual ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.daily_ritual FOR ALL TO anon USING (true) WITH CHECK (true);


-- =============================================================================
-- === Tier 6 : Bien-être ===
-- =============================================================================

-- === 28. self_care_habits ===
-- Habitudes de bien-être (définitions)
CREATE TABLE IF NOT EXISTS self_care_habits (
    id          TEXT    PRIMARY KEY,   -- ex. "walk", "meditate", "read"
    name        TEXT    NOT NULL,
    icon        TEXT,
    category    TEXT,
    is_default  BOOLEAN DEFAULT FALSE,
    order_index INT     DEFAULT 0
);

ALTER TABLE public.self_care_habits ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.self_care_habits FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 29. self_care_logs ===
-- Logs de complétion des habitudes
CREATE TABLE IF NOT EXISTS self_care_logs (
    id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    date        DATE    NOT NULL,
    habit_id    TEXT    NOT NULL REFERENCES self_care_habits(id) ON DELETE CASCADE,
    UNIQUE (date, habit_id)
);

CREATE INDEX IF NOT EXISTS idx_self_care_logs_date ON self_care_logs (date DESC);

ALTER TABLE public.self_care_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.self_care_logs FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 30. sleep_records ===
-- Enregistrements de sommeil — avec contrainte UNIQUE(date) (migration 011)
CREATE TABLE IF NOT EXISTS sleep_records (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    date            DATE        NOT NULL UNIQUE,
    duration_hours  NUMERIC,
    quality         SMALLINT    CHECK (quality BETWEEN 1 AND 10),
    notes           TEXT,
    logged_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sleep_records_date ON sleep_records (date DESC);

ALTER TABLE public.sleep_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.sleep_records FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 31. breathwork_sessions ===
-- Séances de respiration — version consolidée (legacy schema.sql + Spirit migration 033)
-- Note : migration 042 a corrigé des colonnes NOT NULL → nullable pour rétrocompatibilité
CREATE TABLE IF NOT EXISTS breathwork_sessions (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Colonnes Spirit Pillar (migration 033 — version principale)
    protocol        TEXT        CHECK (protocol IN ('calm_storm', 'ignite', 'stillness')),
    duration_sec    INTEGER,
    cycles          INTEGER     NOT NULL DEFAULT 0,
    started_at      TIMESTAMPTZ DEFAULT NOW(),
    triggered_from  TEXT        NOT NULL DEFAULT 'standalone'
                        CHECK (triggered_from IN ('standalone', 'arsenal', 'ritual', 'morning')),
    -- Colonnes legacy (schema.sql initial — conservées pour rétrocompatibilité)
    technique       TEXT,                              -- box | 4-7-8 | wim_hof | coherence
    technique_id    TEXT,                              -- migration 011
    duration_min    INT,
    notes           TEXT,
    logged_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_breathwork_sessions_date ON breathwork_sessions (started_at DESC);

ALTER TABLE public.breathwork_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.breathwork_sessions FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 32. meditation_sessions ===
-- Séances de méditation (migration 033)
CREATE TABLE IF NOT EXISTS meditation_sessions (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    planned_sec     INTEGER     NOT NULL,
    actual_sec      INTEGER     NOT NULL,
    bell_interval   INTEGER     NOT NULL DEFAULT 0,
    started_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed       BOOLEAN     NOT NULL DEFAULT FALSE
);

ALTER TABLE public.meditation_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.meditation_sessions FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 33. spirit_journal ===
-- Journal sacré du pilier Spirit (migration 033) — protégé par Face ID iOS
CREATE TABLE IF NOT EXISTS spirit_journal (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    date         DATE        NOT NULL UNIQUE,
    grateful_for TEXT,
    conquered    TEXT,
    haunting     TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.spirit_journal ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.spirit_journal FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 34. spirit_config ===
-- Configuration du pilier Spirit — table single-row (migration 033)
CREATE TABLE IF NOT EXISTS spirit_config (
    id                  INTEGER     PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    integration_phoenix BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.spirit_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.spirit_config FOR ALL TO anon USING (true) WITH CHECK (true);


-- =============================================================================
-- === Tier 7 : Coaching & Profil ===
-- =============================================================================

-- === 35. coach_history ===
-- Historique des conversations avec le coach IA
CREATE TABLE IF NOT EXISTS coach_history (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    mode                TEXT,                   -- coach | analyst | planner | etc.
    user_message        TEXT,
    assistant_response  TEXT
);

CREATE INDEX IF NOT EXISTS idx_coach_history_created ON coach_history (created_at DESC);

ALTER TABLE public.coach_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.coach_history FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 36. user_profile ===
-- Profil utilisateur — table single-row
-- Colonnes ajoutées par migrations :
--   022 : coach_memory JSONB
--   023 : active_program_id (TEXT → UUID via migration 047) + session_override
--   036 : coach_war_room_shared
CREATE TABLE IF NOT EXISTS user_profile (
    id                      INT     PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    name                    TEXT,
    age                     SMALLINT,
    sex                     CHAR(1) CHECK (sex IN ('M', 'F')),
    weight                  NUMERIC,           -- poids corporel informatif (non synchronisé depuis body_weight_logs)
    height                  SMALLINT,          -- cm
    level                   TEXT,              -- beginner | intermediate | advanced
    goal                    TEXT,              -- bulk | cut | maintain | recomp
    units                   TEXT    DEFAULT 'kg',
    photo_b64               TEXT,              -- legacy : base64 data URL (déprécié → photo_url)
    photo_url               TEXT,              -- Supabase Storage public URL (bucket profile-photos)
    coach_memory            JSONB   DEFAULT '[]'::jsonb,    -- mémoire coach persistante (migration 022)
    active_program_id       UUID    REFERENCES programs(id) ON DELETE SET NULL,  -- migration 023 + fix 047
    session_override        JSONB,                          -- {date, session} — override manuel du jour (migration 023)
    coach_war_room_shared   BOOLEAN NOT NULL DEFAULT FALSE, -- opt-in partage War Room avec coach (migration 036)
    created_at              TIMESTAMPTZ DEFAULT NOW(),
    updated_at              TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO user_profile (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.user_profile ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.user_profile FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 37. deload_state ===
-- État du déload actif — table single-row
CREATE TABLE IF NOT EXISTS deload_state (
    id          INT     PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    active      BOOLEAN DEFAULT FALSE,
    started_at  DATE,
    reason      TEXT
);

INSERT INTO deload_state (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.deload_state ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.deload_state FOR ALL TO anon USING (true) WITH CHECK (true);


-- =============================================================================
-- === Tier 8 : Caractère & Identité ===
-- =============================================================================

-- === 38. oaths ===
-- Serments fondateurs — protégés par Face ID iOS (migration 034)
CREATE TABLE IF NOT EXISTS oaths (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    text          TEXT        NOT NULL,
    version       INTEGER     NOT NULL DEFAULT 1,
    word_count    INTEGER,
    written_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    superseded_at TIMESTAMPTZ
);

ALTER TABLE public.oaths ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.oaths FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 39. oath_recalls ===
-- Rappels de serment — ON DELETE CASCADE (migration 043 corrige migration 034)
CREATE TABLE IF NOT EXISTS oath_recalls (
    id       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    oath_id  UUID        REFERENCES oaths(id) ON DELETE CASCADE,
    trigger  TEXT        NOT NULL CHECK (trigger IN ('streak_reset', 'phoenix_decline', 'emergency', 'milestone', 'manual')),
    shown_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.oath_recalls ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.oath_recalls FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 40. seasons ===
-- Saisons narratives de la transformation (migration 035)
CREATE TABLE IF NOT EXISTS seasons (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    number          INTEGER     NOT NULL,
    started_at      DATE        NOT NULL,
    ended_at        DATE,
    status          TEXT        NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active', 'completed')),
    generated_title TEXT,
    custom_title    TEXT,
    dominant_arc    TEXT        CHECK (dominant_arc IN (
                        'rebirth', 'comeback', 'war', 'breakthrough',
                        'ascent', 'foundation', 'plateau', 'descent')),
    personal_note   TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.seasons ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.seasons FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 41. season_snapshots ===
-- Instantanés de données par saison — ON DELETE CASCADE (migration 043 corrige migration 035)
CREATE TABLE IF NOT EXISTS season_snapshots (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    season_id       UUID        REFERENCES seasons(id) ON DELETE CASCADE,
    type            TEXT        NOT NULL CHECK (type IN ('start', 'end')),
    captured_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    weight_lbs                  NUMERIC,
    body_fat_pct                NUMERIC,

    phoenix_avg                 NUMERIC,
    phoenix_workout_avg         NUMERIC,
    phoenix_stress_avg          NUMERIC,
    phoenix_nutrition_avg       NUMERIC,
    phoenix_resilience_avg      NUMERIC,
    phoenix_spirit_avg          NUMERIC,

    pss_score                   INTEGER,
    war_room_streak             INTEGER,
    top_prs                     JSONB,

    ritual_completion_rate      NUMERIC,
    avg_sleep_hrs               NUMERIC,
    avg_calories                NUMERIC,
    avg_protein_g               NUMERIC,

    breathwork_sessions_total   INTEGER,
    meditation_minutes_total    INTEGER,
    journal_entries_total       INTEGER
);

ALTER TABLE public.season_snapshots ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.season_snapshots FOR ALL TO anon USING (true) WITH CHECK (true);


-- =============================================================================
-- === Tier 9 : Features avancées ===
-- =============================================================================

-- === 42. war_room_config ===
-- Configuration War Room — table single-row (migration 032)
-- Ultra-privé : non inclus dans exports ni analytics. Protégé par Face ID iOS.
CREATE TABLE IF NOT EXISTS war_room_config (
    id                    INTEGER     PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    war_start_date        DATE,
    substance_label       TEXT        NOT NULL DEFAULT 'ennemi',
    integration_phoenix   BOOLEAN     NOT NULL DEFAULT FALSE,
    integration_readiness BOOLEAN     NOT NULL DEFAULT TRUE,
    integration_ai_coach  BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.war_room_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.war_room_config FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 43. war_room_battles ===
-- Batailles quotidiennes (migration 032)
CREATE TABLE IF NOT EXISTS war_room_battles (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    date        DATE        NOT NULL UNIQUE,
    status      TEXT        NOT NULL CHECK (status IN ('victory', 'lost', 'active')),
    notes       TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.war_room_battles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.war_room_battles FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 44. war_room_triggers ===
-- Déclencheurs de tentation loggés (migration 032)
CREATE TABLE IF NOT EXISTS war_room_triggers (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    date         DATE        NOT NULL DEFAULT CURRENT_DATE,
    logged_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    context      TEXT        NOT NULL DEFAULT 'custom'
                     CHECK (context IN ('stress','social','boredom','pain','celebration','exhaustion','custom')),
    context_note TEXT,
    intensity    SMALLINT    NOT NULL DEFAULT 3 CHECK (intensity BETWEEN 1 AND 5),
    yielded      BOOLEAN     NOT NULL DEFAULT FALSE,
    held_with    TEXT[],
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wr_triggers_date ON war_room_triggers (date DESC);

ALTER TABLE public.war_room_triggers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.war_room_triggers FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 45. war_room_arsenal ===
-- Arsenal de contre-mesures (migration 032)
CREATE TABLE IF NOT EXISTS war_room_arsenal (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    label        TEXT        NOT NULL,
    category     TEXT        NOT NULL DEFAULT 'other'
                     CHECK (category IN ('call','physical','breath','mental','environment','other')),
    use_count    INTEGER     NOT NULL DEFAULT 0,
    last_used_at TIMESTAMPTZ,
    sort_order   INTEGER     NOT NULL DEFAULT 0,
    active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.war_room_arsenal ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.war_room_arsenal FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 46. time_capsules ===
-- Capsules temporelles (migration 027)
CREATE TABLE IF NOT EXISTS time_capsules (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    unlock_at        TIMESTAMPTZ NOT NULL,
    unlocked_at      TIMESTAMPTZ,
    duration_months  INTEGER     NOT NULL CHECK (duration_months IN (1, 3, 6)),
    message          TEXT,
    snapshot         JSONB       NOT NULL DEFAULT '{}',
    is_opened        BOOLEAN     NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_time_capsules_unlock_at ON time_capsules (unlock_at);
CREATE INDEX IF NOT EXISTS idx_time_capsules_is_opened ON time_capsules (is_opened);

ALTER TABLE public.time_capsules ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.time_capsules FOR ALL TO anon USING (true) WITH CHECK (true);


-- =============================================================================
-- === Tier 10 : Système ===
-- =============================================================================

-- === 47. gym_contributions ===
-- Contributions crowdsourcées — anonymes, sans user_id (migration 037)
CREATE TABLE IF NOT EXISTS gym_contributions (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id          TEXT            NOT NULL,
    gym_name        TEXT,
    latitude        DOUBLE PRECISION,
    longitude       DOUBLE PRECISION,
    drop_in_price   NUMERIC(7, 2),
    equipment       TEXT[]          DEFAULT '{}',
    vibe_hardcore   SMALLINT        CHECK (vibe_hardcore BETWEEN 1 AND 5),
    vibe_crowded    SMALLINT        CHECK (vibe_crowded BETWEEN 1 AND 5),
    vibe_music      SMALLINT        CHECK (vibe_music BETWEEN 1 AND 5),
    created_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_gym_contributions_gym_id ON gym_contributions (gym_id);

ALTER TABLE public.gym_contributions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.gym_contributions FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 48. user_gym_history ===
-- Historique des visites de gym par utilisateur (migration 037)
CREATE TABLE IF NOT EXISTS user_gym_history (
    id          UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id      TEXT            NOT NULL,
    gym_name    TEXT,
    latitude    DOUBLE PRECISION,
    longitude   DOUBLE PRECISION,
    visited_at  TIMESTAMPTZ     DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_gym_history_visited ON user_gym_history (visited_at DESC);

ALTER TABLE public.user_gym_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.user_gym_history FOR ALL TO anon USING (true) WITH CHECK (true);


-- === 49. schema_migrations ===
-- Tracker des migrations appliquées (migration 026)
CREATE TABLE IF NOT EXISTS public.schema_migrations (
    version    TEXT        PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.schema_migrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.schema_migrations FOR ALL TO anon USING (true) WITH CHECK (true);

-- Marquer toutes les migrations comme appliquées (bootstrap idempotent)
INSERT INTO public.schema_migrations (version) VALUES
    ('nutrition_entries'),
    ('add_sets_json'),
    ('002_multi_programs'),
    ('003_session_type'),
    ('004_food_catalog'),
    ('005_nutrition_intel'),
    ('006_rpe_numeric'),
    ('007_load_profile'),
    ('008_fix_categories'),
    ('009_fix_categories_2'),
    ('010_session_name'),
    ('011_kv_migration'),
    ('012_workout_sessions_completed'),
    ('013_nutrition_scan'),
    ('014_generated_programs'),
    ('015_programs_cycle_start'),
    ('016_per_set_volume_views'),
    ('017_recovery_hr_moments'),
    ('018_meal_templates'),
    ('019_nutrition_dynamic_goals'),
    ('020_soft_delete_exercises'),
    ('021_day_type_targets'),
    ('022_coach_memory'),
    ('023_active_program_session_override'),
    ('024_exercise_logs_rpe_pain_zone'),
    ('025_pss_unique_date_type'),
    ('026_schema_migrations_tracker'),
    ('027_time_capsules'),
    ('028_plateau_alerts'),
    ('029_neck_cm_weight_deprecation'),
    ('030_meal_templates_rls'),
    ('031_fix_set_updated_at_search_path'),
    ('032_war_room'),
    ('033_spirit'),
    ('034_oath'),
    ('035_seasons'),
    ('036_coach_war_room_shared'),
    ('037_gym_finder'),
    ('038_recovery_fatigue'),
    ('039_hydration_logs'),
    ('040_1rm_brzycki'),
    ('041_view_security_invoker'),
    ('042_fix_breathwork_sessions'),
    ('043_fix_oath_season_cascade'),
    ('044_fix_mood_logs_pss_fk'),
    ('045_fix_indexes'),
    ('046_fix_not_null_constraints'),
    ('047_fix_user_profile_active_program_id')
ON CONFLICT (version) DO NOTHING;


-- === 50. ai_rate_limit ===
-- Limitation de taux API IA (cross-worker, Vercel-safe)
CREATE TABLE IF NOT EXISTS ai_rate_limit (
    hour_key TEXT    PRIMARY KEY,   -- ex. "2026-04-06T14" (heure UTC)
    count    INTEGER NOT NULL DEFAULT 0
);

ALTER TABLE public.ai_rate_limit ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.ai_rate_limit FOR ALL TO anon USING (true) WITH CHECK (true);


-- =============================================================================
-- === VUES ANALYTIQUES ===
-- =============================================================================

-- v_exercise_current
-- Retourne le dernier poids logué, les dernières reps, et le nombre de séances par exercice.
-- Utilisation : "quel est le poids courant pour le Bench Press ?"
-- 1RM estimé : Epley ≤10 reps, Brzycki 11-20 reps, NULL >20 reps (voir migration 040).
DROP VIEW IF EXISTS v_exercise_current;
CREATE VIEW v_exercise_current AS
SELECT
    sub.exercise_id,
    sub.exercise_name,
    sub.type,
    sub.latest_weight,
    sub.latest_reps,
    sub.session_count,
    -- 1RM estimé : Epley ≤10 reps, Brzycki 11-20 reps, NULL >20 reps
    CASE
        WHEN sub.latest_weight IS NULL OR sub.latest_weight <= 0 THEN NULL
        WHEN sub.max_reps > 20                                   THEN NULL
        WHEN sub.max_reps > 10
            THEN ROUND(sub.latest_weight * (36.0 / (37 - sub.max_reps)), 1)
        ELSE ROUND(sub.latest_weight * (1 + sub.max_reps::NUMERIC / 30), 1)
    END                                                          AS estimated_1rm,
    CASE
        WHEN sub.latest_weight IS NULL OR sub.latest_weight <= 0 THEN NULL
        WHEN sub.max_reps > 20 THEN 'none'
        WHEN sub.max_reps > 15 THEN 'low'
        WHEN sub.max_reps > 10 THEN 'medium'
        ELSE                        'high'
    END                                                          AS estimated_1rm_confidence
FROM (
    SELECT
        e.id                        AS exercise_id,
        e.name                      AS exercise_name,
        e.type,
        latest.weight               AS latest_weight,
        latest.reps                 AS latest_reps,
        session_counts.session_count,
        COALESCE(
            (SELECT MAX(r::INT)
             FROM unnest(string_to_array(latest.reps, ',')) AS r
             WHERE r ~ '^\d+$'),
            1
        )                           AS max_reps
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
    ) session_counts ON session_counts.exercise_id = e.id
) sub;


-- v_session_volume
-- Retourne les métriques de volume calculées par séance.
-- volume     = SUM des charges réelles par set depuis sets_json si disponible,
--              sinon weight * total_reps_pour_exercice (fallback legacy)
-- total_sets = COUNT(lignes exercise_logs) — une ligne par exercice par séance
-- total_reps = SUM de toutes les reps individuelles par set sur tous les exercices
-- Note : les exercices au poids de corps (weight IS NULL ou 0) contribuent 0 au volume.
CREATE OR REPLACE VIEW v_session_volume WITH (security_invoker = true) AS
SELECT
    ws.id                                               AS session_id,
    ws.date,
    ws.rpe,
    ws.duration_min,
    ROUND(SUM(
        CASE
            WHEN el.sets_json IS NOT NULL AND jsonb_array_length(el.sets_json) > 0
            THEN (
                SELECT COALESCE(SUM(
                    COALESCE(
                        (s->>'set_volume')::NUMERIC,
                        COALESCE((s->>'weight')::NUMERIC, 0) *
                        COALESCE((s->>'reps')::NUMERIC, 0)
                    )
                ), 0)
                FROM jsonb_array_elements(el.sets_json) AS s
            )
            ELSE COALESCE(el.weight, 0) * COALESCE((
                SELECT SUM(r::INT)
                FROM unnest(string_to_array(el.reps, ',')) AS r
                WHERE r ~ '^\d+$'
            ), 0)
        END
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
-- Agrège le volume de séance par semaine ISO.
-- Utile pour le monitoring de la charge hebdomadaire et la détection de surmenage.
CREATE OR REPLACE VIEW v_weekly_volume WITH (security_invoker = true) AS
SELECT
    DATE_TRUNC('week', ws.date)                     AS week_start,
    EXTRACT(WEEK FROM ws.date)::INT                 AS week_number,
    EXTRACT(YEAR FROM ws.date)::INT                 AS year,
    ROUND(SUM(
        CASE
            WHEN el.sets_json IS NOT NULL AND jsonb_array_length(el.sets_json) > 0
            THEN (
                SELECT COALESCE(SUM(
                    COALESCE(
                        (s->>'set_volume')::NUMERIC,
                        COALESCE((s->>'weight')::NUMERIC, 0) *
                        COALESCE((s->>'reps')::NUMERIC, 0)
                    )
                ), 0)
                FROM jsonb_array_elements(el.sets_json) AS s
            )
            ELSE COALESCE(el.weight, 0) * COALESCE((
                SELECT SUM(r::INT)
                FROM unnest(string_to_array(el.reps, ',')) AS r
                WHERE r ~ '^\d+$'
            ), 0)
        END
    ), 2)                                           AS total_volume,
    COUNT(DISTINCT ws.id)                           AS session_count,
    COUNT(el.id)                                    AS total_sets
FROM workout_sessions ws
LEFT JOIN exercise_logs el ON el.session_id = ws.id
GROUP BY DATE_TRUNC('week', ws.date), EXTRACT(WEEK FROM ws.date), EXTRACT(YEAR FROM ws.date)
ORDER BY week_start DESC;
