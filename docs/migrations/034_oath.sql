-- 034_oath.sql — The Oath: founding commitment, biometric-locked, versioned
-- No dollar-quoted functions, no CREATE INDEX.

CREATE TABLE IF NOT EXISTS oaths (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    text          TEXT NOT NULL,
    version       INTEGER NOT NULL DEFAULT 1,
    word_count    INTEGER,
    written_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    superseded_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS oath_recalls (
    id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    oath_id  UUID REFERENCES oaths(id),
    trigger  TEXT NOT NULL CHECK (trigger IN ('streak_reset', 'phoenix_decline', 'emergency', 'milestone', 'manual')),
    shown_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- RLS: permissive (single-user app) — oath privacy enforced at iOS biometric layer
ALTER TABLE oaths        ENABLE ROW LEVEL SECURITY;
ALTER TABLE oath_recalls ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS oath_all        ON oaths;
DROP POLICY IF EXISTS oath_recall_all ON oath_recalls;

CREATE POLICY oath_all        ON oaths        FOR ALL TO anon USING (true);
CREATE POLICY oath_recall_all ON oath_recalls FOR ALL TO anon USING (true);
