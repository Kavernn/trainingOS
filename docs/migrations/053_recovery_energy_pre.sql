-- Migration 053 : Ajout de energy_pre dans recovery_logs
-- Énergie perçue pre-workout — SMALLINT nullable, CHECK 1..10
-- Zéro modification des données existantes

ALTER TABLE recovery_logs
  ADD COLUMN energy_pre SMALLINT
    CHECK (energy_pre BETWEEN 1 AND 10);
