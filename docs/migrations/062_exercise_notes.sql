-- Migration 062: add notes column to exercise_logs
-- One free-text note per exercise per session (nullable, no impact on existing rows)
ALTER TABLE public.exercise_logs
    ADD COLUMN IF NOT EXISTS notes TEXT;
