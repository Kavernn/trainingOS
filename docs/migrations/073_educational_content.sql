-- 073 : educational_content — capsules éducatives Coach (kine, anatomie, sports science, well-being, nutrition).
-- Lookup déterministe par exercise_id / movement_pattern / muscle_specific.
-- Valeurs de lien = valeurs prod réelles (Title Case anglais pour patterns, français pour muscles).
CREATE TABLE IF NOT EXISTS educational_content (
    id               BIGSERIAL PRIMARY KEY,
    category         TEXT NOT NULL,
    title            TEXT NOT NULL,
    body             TEXT NOT NULL,
    exercise_id      UUID REFERENCES exercises(id) ON DELETE SET NULL,
    movement_pattern TEXT,
    muscle_specific  TEXT,
    tags             TEXT[] NOT NULL DEFAULT '{}',
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE educational_content ENABLE ROW LEVEL SECURITY;

CREATE POLICY "educational_content_read" ON educational_content
    FOR SELECT TO anon USING (true);
