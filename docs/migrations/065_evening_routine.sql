-- Migration 065 — Routine de soir
-- Checklist comportementale indépendante du rituel soir (jugement/intention).
-- Toutes les colonnes nullable — zéro impact sur l'historique existant.

ALTER TABLE daily_ritual
    ADD COLUMN IF NOT EXISTS routine_no_food          BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS routine_dim_lights        BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS routine_shower            BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS routine_connection        BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS routine_deconnect         BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS routine_priorities_done   BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS routine_bedtime_ok        BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS routine_completed_at      TIMESTAMPTZ;
