-- Migration 015: Ajoute cycle_start_date à programs pour calcul mésocycle 8 semaines
-- Run once in the Supabase SQL Editor.

ALTER TABLE programs ADD COLUMN IF NOT EXISTS cycle_start_date DATE;

-- Programme UL/PPL v1 démarré le 2026-04-25
UPDATE programs SET cycle_start_date = '2026-04-25' WHERE cycle_start_date IS NULL;
