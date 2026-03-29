-- Migration 003: add session_type column to workout_sessions
-- Run once on existing Supabase database.

ALTER TABLE public.workout_sessions
    ADD COLUMN IF NOT EXISTS session_type TEXT NOT NULL DEFAULT 'morning';

-- Back-fill: sessions with is_second=true become 'evening', bonus sessions keep their type
UPDATE public.workout_sessions
    SET session_type = 'evening'
    WHERE is_second = TRUE AND session_type = 'morning';

-- Recreate unique constraint now that the column exists
-- (drop old one first in case it was partially created)
ALTER TABLE public.workout_sessions
    DROP CONSTRAINT IF EXISTS workout_sessions_date_session_type_key;

ALTER TABLE public.workout_sessions
    ADD CONSTRAINT workout_sessions_date_session_type_key UNIQUE (date, session_type);
