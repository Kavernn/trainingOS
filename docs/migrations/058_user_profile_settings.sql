-- 058 — user_profile : sleep_goal_hours + hrv_sensitivity
-- Paramètres utilisateur pour le scoring readiness et les zones HRV.
-- Valeurs par défaut = comportement actuel hardcodé (zéro changement si non configuré).

ALTER TABLE user_profile
    ADD COLUMN IF NOT EXISTS sleep_goal_hours NUMERIC(4,1) DEFAULT 8.0,
    ADD COLUMN IF NOT EXISTS hrv_sensitivity  TEXT         DEFAULT 'standard';
