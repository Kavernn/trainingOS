-- Migration 002: Multi-programmes + fix weekly_schedule slot
-- Run once in the Supabase SQL Editor.

-- ─────────────────────────────────────────────────────────
-- 1. Corriger weekly_schedule : ajouter colonne slot + PK composite
-- ─────────────────────────────────────────────────────────

ALTER TABLE weekly_schedule
    ADD COLUMN IF NOT EXISTS slot TEXT NOT NULL DEFAULT 'morning';

-- Recréer la PK en composite (day_name, slot)
ALTER TABLE weekly_schedule DROP CONSTRAINT IF EXISTS weekly_schedule_pkey;
ALTER TABLE weekly_schedule ADD PRIMARY KEY (day_name, slot);

-- ─────────────────────────────────────────────────────────
-- 2. Créer la table programs
-- ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS programs (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name       TEXT        NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Policies (même niveau que les autres tables)
ALTER TABLE programs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "allow_all_programs" ON programs FOR ALL USING (true) WITH CHECK (true);

-- ─────────────────────────────────────────────────────────
-- 3. Ajouter program_id à program_sessions
-- ─────────────────────────────────────────────────────────

ALTER TABLE program_sessions
    ADD COLUMN IF NOT EXISTS program_id UUID REFERENCES programs(id) ON DELETE CASCADE;

-- ─────────────────────────────────────────────────────────
-- 4. Migrer les sessions existantes vers un programme par défaut
-- ─────────────────────────────────────────────────────────

DO $$
DECLARE
    default_id UUID;
BEGIN
    -- Créer "Programme 1" si pas encore de programmes
    IF NOT EXISTS (SELECT 1 FROM programs LIMIT 1) THEN
        INSERT INTO programs (name) VALUES ('Programme 1') RETURNING id INTO default_id;
    ELSE
        SELECT id INTO default_id FROM programs ORDER BY created_at LIMIT 1;
    END IF;

    -- Assigner toutes les sessions sans program_id au programme par défaut
    UPDATE program_sessions SET program_id = default_id WHERE program_id IS NULL;
END $$;

-- Rendre program_id NOT NULL maintenant que toutes les lignes sont remplies
ALTER TABLE program_sessions ALTER COLUMN program_id SET NOT NULL;

-- ─────────────────────────────────────────────────────────
-- 5. Remplacer l'index unique global par un index par programme
-- ─────────────────────────────────────────────────────────

ALTER TABLE program_sessions DROP CONSTRAINT IF EXISTS program_sessions_name_key;
CREATE UNIQUE INDEX IF NOT EXISTS idx_program_sessions_program_name
    ON program_sessions (program_id, name);
