-- Migration 061 — tomorrow_intention dans daily_ritual
-- Intention prise le soir pour le lendemain (flow soir enrichi).
-- Nullable — zéro impact sur les données historiques.
ALTER TABLE daily_ritual
  ADD COLUMN IF NOT EXISTS tomorrow_intention TEXT;
