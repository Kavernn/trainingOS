-- MIGRATION 087b — Locked In 2027 : contract (drop ancienne clé 2-col)
-- Étape finale de l'expand/contract démarré en 087a.
-- Gate passé (2026-08-03) : logs prod portent side='both', 0 doublon → upsert cible
-- bien la clé 3-col UNIQUE(session_id,exercise_id,side). L'ancienne 2-col est safe à droper.
-- Safe re-run : IF EXISTS.

ALTER TABLE public.exercise_logs
    DROP CONSTRAINT IF EXISTS exercise_logs_session_id_exercise_id_key;
