-- Migration 060 — Colonnes bedtime / wake_time dans recovery_logs
-- Stockées en TEXT "HH:mm" (ex: "23:15", "06:47").
-- Nullable — zéro impact sur les données existantes.
ALTER TABLE recovery_logs
  ADD COLUMN IF NOT EXISTS bedtime  TEXT,
  ADD COLUMN IF NOT EXISTS wake_time TEXT;
