-- Migration 012: add completed flag to workout_sessions
-- Used by /api/log_session completion flow.
-- Safe to run multiple times.

ALTER TABLE public.workout_sessions
    ADD COLUMN IF NOT EXISTS completed BOOLEAN NOT NULL DEFAULT FALSE;
