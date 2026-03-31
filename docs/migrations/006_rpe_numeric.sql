-- Migration 006: change rpe column from SMALLINT to NUMERIC(4,1)
-- Fixes RPE values being rounded (e.g. 7.5 stored as 8).

ALTER TABLE public.workout_sessions
    ALTER COLUMN rpe TYPE NUMERIC(4,1);

ALTER TABLE public.workout_sessions
    DROP CONSTRAINT IF EXISTS workout_sessions_rpe_check;

ALTER TABLE public.workout_sessions
    ADD CONSTRAINT workout_sessions_rpe_check CHECK (rpe BETWEEN 1 AND 10);

-- Also fix hiit_logs if rpe column exists there
ALTER TABLE public.hiit_logs
    ALTER COLUMN rpe TYPE NUMERIC(4,1);
