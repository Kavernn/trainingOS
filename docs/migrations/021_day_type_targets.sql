-- Migration 021: add day_type_targets JSONB column to nutrition_settings
-- Stores per-day-type calorie + glucide targets (light / moderate / heavy / rest)

ALTER TABLE nutrition_settings
  ADD COLUMN IF NOT EXISTS day_type_targets JSONB;
