-- MIGRATION 087a — Locked In 2027 : expand (2026-08-02)
--
-- Étape 1 d'un expand/contract pour rotation de l'UNIQUE sur exercise_logs.
-- Le code (Vercel) et le SQL (Supabase dashboard) ne déploient pas ensemble.
-- 087a ajoute la nouvelle clé (3-col) sans droper l'ancienne (2-col) → PostgREST
-- peut cibler l'une OU l'autre pendant la fenêtre de désynchro.
-- 087b (après code déployé + vérifié) dropera l'ancienne clé.
--
-- Aucun log per-side n'est possible avant chantier 2 (iOS n'a pas la carte) →
-- l'ancien UNIQUE 2-col ne bloque rien pendant la coexistence.
--
-- Préflight A : catalogue exercises → 124 reps + 4 time + 0 NULL → CHECK safe.
-- Préflight B : 622 logs (579 reps, 43 time), aucun orphelin FK.
-- Nom de la contrainte UNIQUE existante confirmé par pg_constraint :
--   exercise_logs_session_id_exercise_id_key (conservée, dropée en 087b).
--
-- Décisions gelées :
--   - tracking_type devient un vocabulaire fermé de 7 valeurs (CHECK).
--   - exercise_logs gagne distance_m, intensity, protocol_completed (nullable)
--     + side (NOT NULL DEFAULT 'both' → 622 rows historiques deviennent 'both').
--   - intensity = NUMERIC (l'unité est résolue par l'exo au chantier 2, pas
--     dans la colonne : %1RM, cm, m/s — un seul champ générique).
--
-- Safe re-run : ADD COLUMN IF NOT EXISTS + DROP CONSTRAINT IF EXISTS avant ADD.
-- Pas de dollar-quoting (Supabase dashboard le casse), pas de CREATE INDEX.

-- === exercises (catalogue) : CHECK sur tracking_type ===
ALTER TABLE public.exercises
    DROP CONSTRAINT IF EXISTS exercises_tracking_type_check;
ALTER TABLE public.exercises
    ADD  CONSTRAINT exercises_tracking_type_check
    CHECK (tracking_type IN ('reps','time','carry','plyo','cardio','interval','protocol'));

-- === exercise_logs : 4 nouvelles colonnes ===
ALTER TABLE public.exercise_logs ADD COLUMN IF NOT EXISTS distance_m         NUMERIC;
ALTER TABLE public.exercise_logs ADD COLUMN IF NOT EXISTS intensity          NUMERIC;
ALTER TABLE public.exercise_logs ADD COLUMN IF NOT EXISTS protocol_completed BOOLEAN;
ALTER TABLE public.exercise_logs ADD COLUMN IF NOT EXISTS side               TEXT NOT NULL DEFAULT 'both';

ALTER TABLE public.exercise_logs DROP CONSTRAINT IF EXISTS exercise_logs_side_check;
ALTER TABLE public.exercise_logs
    ADD  CONSTRAINT exercise_logs_side_check
    CHECK (side IN ('left','right','both'));

-- === exercise_logs : ADD nouvelle UNIQUE (l'ancienne coexiste, dropée en 087b) ===
ALTER TABLE public.exercise_logs DROP CONSTRAINT IF EXISTS exercise_logs_session_id_exercise_id_side_key;
ALTER TABLE public.exercise_logs
    ADD  CONSTRAINT exercise_logs_session_id_exercise_id_side_key
    UNIQUE (session_id, exercise_id, side);
