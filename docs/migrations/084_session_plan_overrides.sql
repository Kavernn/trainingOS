-- 084_session_plan_overrides.sql
-- Étape 3 du flow bonus : déplacement d'exercices planifiés entre séances
-- matin↔soir (et bonus en étape 4). Ne mute JAMAIS le programme template
-- (program_sessions, weekly_schedule) — override scopé strictement à une date.
--
-- Contrainte doctrinale : un exercice avec un exercise_log pour (date, exercise_id)
-- n'est JAMAIS déplaçable (garde-fou zéro-modif-historique). Le check est côté
-- endpoint POST /api/move_planned_exercise, la table n'a pas de FK vers exercise_logs.
--
-- UNIQUE (date, exercise_id) — un même exo ne peut avoir qu'un seul override actif
-- par jour. Re-déplacement = UPSERT (update in place, pas doublon).

CREATE TABLE IF NOT EXISTS session_plan_overrides (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    date DATE NOT NULL,
    exercise_id UUID NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
    from_session_type TEXT NOT NULL CHECK (from_session_type IN ('morning', 'evening', 'bonus')),
    to_session_type   TEXT NOT NULL CHECK (to_session_type   IN ('morning', 'evening', 'bonus')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (date, exercise_id)
);

ALTER TABLE session_plan_overrides ENABLE ROW LEVEL SECURITY;

CREATE POLICY "anon_all" ON session_plan_overrides
    FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY "service_role_all" ON session_plan_overrides
    FOR ALL TO service_role USING (true) WITH CHECK (true);
