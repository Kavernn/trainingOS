-- Migration: add sets_json to exercise_logs
-- Stores per-set weight+reps data for per-set placeholder display on next session

ALTER TABLE exercise_logs
    ADD COLUMN IF NOT EXISTS sets_json JSONB DEFAULT '[]'::jsonb;
