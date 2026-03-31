-- Migration 010: add session_name to workout_sessions
-- Stores the program session name (e.g. "Push A", "Pull B", "Legs")
-- Used by smart progression to match sessions of the same type.

ALTER TABLE public.workout_sessions
    ADD COLUMN IF NOT EXISTS session_name TEXT;

CREATE INDEX IF NOT EXISTS idx_workout_sessions_name
    ON public.workout_sessions (session_name, date DESC);
