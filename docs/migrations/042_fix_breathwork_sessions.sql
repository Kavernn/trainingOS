-- Migration 042 — Réconciliation breathwork_sessions (conflit schema.sql vs 033)
--
-- Problème : deux définitions incompatibles coexistent.
--   schema.sql       → (technique TEXT, duration_min INT, notes TEXT, logged_at TIMESTAMPTZ)
--   migration 033    → (protocol TEXT, duration_sec INT, cycles INT, started_at TIMESTAMPTZ, triggered_from TEXT)
--
-- Si schema.sql a tourné en premier sur la DB, migration 033 était silencieusement
-- skippée (CREATE TABLE IF NOT EXISTS). Résultat : les colonnes Spirit Pillar manquent,
-- l'app iOS crash au moindre appel breathwork.
--
-- Fix : ALTER TABLE IF NOT EXISTS pour ajouter les colonnes Spirit manquantes.
-- On ne supprime PAS les anciennes colonnes (technique, duration_min, notes, logged_at)
-- pour éviter toute perte de données existantes.

ALTER TABLE breathwork_sessions
    ADD COLUMN IF NOT EXISTS protocol       TEXT
        CHECK (protocol IN ('calm_storm', 'ignite', 'stillness')),
    ADD COLUMN IF NOT EXISTS duration_sec   INTEGER,
    ADD COLUMN IF NOT EXISTS cycles         INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS started_at     TIMESTAMPTZ DEFAULT now(),
    ADD COLUMN IF NOT EXISTS triggered_from TEXT NOT NULL DEFAULT 'standalone'
        CHECK (triggered_from IN ('standalone', 'arsenal', 'ritual', 'morning'));

-- Marquer comme appliquée dans le tracker
INSERT INTO public.schema_migrations (version)
VALUES ('042_fix_breathwork_sessions')
ON CONFLICT (version) DO NOTHING;
