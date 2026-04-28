-- Migration 017 — recovery_logs: add intraday HR columns
-- These columns were referenced in the API and Swift model but never added to the DB,
-- causing every logRecovery call to fail silently (upsert returned false → HTTP 500).

ALTER TABLE recovery_logs ADD COLUMN IF NOT EXISTS hr_morning      SMALLINT;
ALTER TABLE recovery_logs ADD COLUMN IF NOT EXISTS hr_post_workout SMALLINT;
ALTER TABLE recovery_logs ADD COLUMN IF NOT EXISTS hr_evening      SMALLINT;
