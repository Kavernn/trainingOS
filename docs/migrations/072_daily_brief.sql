-- 072 : daily_brief — briefing quotidien Coach (un par user par jour, caché serveur)
CREATE TABLE IF NOT EXISTS daily_brief (
    id           BIGSERIAL PRIMARY KEY,
    user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    date         DATE NOT NULL,
    use_quote    BOOLEAN NOT NULL DEFAULT TRUE,
    mot          TEXT,
    lecture      TEXT NOT NULL,
    recommandation JSONB NOT NULL DEFAULT '[]',
    generated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, date)
);

ALTER TABLE daily_brief ENABLE ROW LEVEL SECURITY;

CREATE POLICY "daily_brief_self" ON daily_brief
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
