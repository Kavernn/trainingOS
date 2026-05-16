-- Migration 024: add rpe and pain_zone to exercise_logs
-- These columns were already referenced in upsert_exercise_log_direct() (db.py)
-- but were missing from the schema, causing silent failures on every write.

ALTER TABLE public.exercise_logs
    ADD COLUMN IF NOT EXISTS rpe       NUMERIC(4,1) CHECK (rpe BETWEEN 1 AND 10),
    ADD COLUMN IF NOT EXISTS pain_zone TEXT;
