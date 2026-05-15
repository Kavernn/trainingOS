-- Migration 023: add active_program_id and session_override to user_profile
-- active_program_id : UUID of the user's chosen active programme
-- session_override  : JSONB {date, session} — today's manual session override

ALTER TABLE public.user_profile
    ADD COLUMN IF NOT EXISTS active_program_id TEXT,
    ADD COLUMN IF NOT EXISTS session_override   JSONB;
