-- Migration 036: add coach_war_room_shared flag to user_profile
-- Allows users to explicitly opt-in to sharing War Room stats with the AI coach.
-- Default false — coach has zero knowledge of War Room unless toggled on.

ALTER TABLE user_profile
  ADD COLUMN IF NOT EXISTS coach_war_room_shared boolean NOT NULL DEFAULT false;
