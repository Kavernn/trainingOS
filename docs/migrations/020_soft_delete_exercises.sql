-- Migration 020: Soft delete for exercises
-- Replaces hard DELETE (which cascaded to exercise_logs) with a deleted_at marker.
-- exercise_logs are preserved; program_block_exercises are cleaned up manually.
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ DEFAULT NULL;
CREATE INDEX IF NOT EXISTS idx_exercises_deleted_at ON exercises (deleted_at);
