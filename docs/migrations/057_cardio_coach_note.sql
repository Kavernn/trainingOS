-- Migration 057 : Ajout coach_note dans cardio_logs
-- Conseil personnalisé généré post-session selon type, métriques et données de récupération
-- Nullable — zéro impact sur les logs historiques existants

ALTER TABLE cardio_logs
  ADD COLUMN IF NOT EXISTS coach_note TEXT;
