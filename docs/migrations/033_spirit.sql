-- 033_spirit.sql — Spirit Pillar: breathwork, meditation, journaling
-- Ultra-private for journal (biometric iOS gate). No dollar-quoted functions.

CREATE TABLE IF NOT EXISTS breathwork_sessions (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    protocol       TEXT NOT NULL CHECK (protocol IN ('calm_storm', 'ignite', 'stillness')),
    duration_sec   INTEGER NOT NULL,
    cycles         INTEGER NOT NULL DEFAULT 0,
    started_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    triggered_from TEXT NOT NULL DEFAULT 'standalone'
                     CHECK (triggered_from IN ('standalone', 'arsenal', 'ritual', 'morning'))
);

CREATE TABLE IF NOT EXISTS meditation_sessions (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    planned_sec   INTEGER NOT NULL,
    actual_sec    INTEGER NOT NULL,
    bell_interval INTEGER NOT NULL DEFAULT 0,
    started_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed     BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS spirit_journal (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    date         DATE NOT NULL UNIQUE,
    grateful_for TEXT,
    conquered    TEXT,
    haunting     TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS spirit_config (
    id                  INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    integration_phoenix BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- RLS: permissive (single-user app) — journal privacy enforced at iOS biometric layer
ALTER TABLE breathwork_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE meditation_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE spirit_journal      ENABLE ROW LEVEL SECURITY;
ALTER TABLE spirit_config       ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS spirit_bw_all     ON breathwork_sessions;
DROP POLICY IF EXISTS spirit_med_all    ON meditation_sessions;
DROP POLICY IF EXISTS spirit_journal_al ON spirit_journal;
DROP POLICY IF EXISTS spirit_cfg_all    ON spirit_config;

CREATE POLICY spirit_bw_all     ON breathwork_sessions FOR ALL TO anon USING (true);
CREATE POLICY spirit_med_all    ON meditation_sessions FOR ALL TO anon USING (true);
CREATE POLICY spirit_journal_al ON spirit_journal      FOR ALL TO anon USING (true);
CREATE POLICY spirit_cfg_all    ON spirit_config       FOR ALL TO anon USING (true);
