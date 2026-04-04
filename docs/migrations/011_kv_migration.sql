-- =============================================================================
-- Migration 011 — Fin de migration KV → relational
-- Ajoute les colonnes/tables manquantes pour supprimer la table kv.
-- Safe à exécuter plusieurs fois (IF NOT EXISTS / IF NOT EXISTS).
-- =============================================================================

-- 1. exercises : colonne current_weight (suggestion de poids pour SeanceView pre-fill)
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS current_weight NUMERIC;

-- 2. journal_entries : colonne prompt (question guidée du jour)
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS prompt TEXT;

-- 3. breathwork_sessions : colonnes supplémentaires
ALTER TABLE breathwork_sessions ADD COLUMN IF NOT EXISTS technique_id TEXT;
ALTER TABLE breathwork_sessions ADD COLUMN IF NOT EXISTS duration_sec  INT;
ALTER TABLE breathwork_sessions ADD COLUMN IF NOT EXISTS cycles        INT;

-- 4. sleep_records : contrainte UNIQUE sur date (pour upsert on_conflict=date)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'sleep_records_date_unique'
    ) THEN
        ALTER TABLE sleep_records ADD CONSTRAINT sleep_records_date_unique UNIQUE (date);
    END IF;
END$$;

-- 5. goals_archived : nouvelle table (liste des objectifs archivés)
CREATE TABLE IF NOT EXISTS goals_archived (
    id            UUID  PRIMARY KEY DEFAULT gen_random_uuid(),
    exercise_name TEXT  NOT NULL UNIQUE
);

-- 6. Supprimer la table kv (à exécuter APRÈS avoir validé que tout fonctionne)
-- DROP TABLE IF EXISTS kv;
