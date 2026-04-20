-- Migration 014: Table generated_programs (AI programme generator)
-- Run once in the Supabase SQL Editor.

CREATE TABLE IF NOT EXISTS generated_programs (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    generated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status        TEXT        NOT NULL DEFAULT 'pending_approval',
    -- 'pending_approval' | 'active' | 'archived'
    program_json  JSONB       NOT NULL,
    programme_id  UUID,       -- set after approval, links to programs.id
    notes         TEXT
);

ALTER TABLE generated_programs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "allow_all_generated_programs"
    ON generated_programs FOR ALL USING (true) WITH CHECK (true);
