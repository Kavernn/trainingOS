-- Migration 022 : Coach memory server-side persistence
-- Adds coach_memory JSONB column to user_profile so CoachMemoryStore syncs
-- across devices instead of being local-only (UserDefaults).

ALTER TABLE user_profile
    ADD COLUMN IF NOT EXISTS coach_memory JSONB DEFAULT '[]'::jsonb;
