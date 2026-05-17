-- 032_war_room.sql — The War Room: private combat tracker
-- Ultra-private: these tables are never included in exports or analytics endpoints.

CREATE TABLE IF NOT EXISTS war_room_config (
    id                    INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    war_start_date        DATE,
    substance_label       TEXT NOT NULL DEFAULT 'ennemi',
    integration_phoenix   BOOLEAN NOT NULL DEFAULT FALSE,
    integration_readiness BOOLEAN NOT NULL DEFAULT TRUE,
    integration_ai_coach  BOOLEAN NOT NULL DEFAULT FALSE,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS war_room_battles (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    date       DATE NOT NULL UNIQUE,
    status     TEXT NOT NULL CHECK (status IN ('victory', 'lost', 'active')),
    notes      TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS war_room_triggers (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    date         DATE NOT NULL DEFAULT CURRENT_DATE,
    logged_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    context      TEXT NOT NULL DEFAULT 'custom'
                   CHECK (context IN ('stress','social','boredom','pain','celebration','exhaustion','custom')),
    context_note TEXT,
    intensity    SMALLINT NOT NULL DEFAULT 3 CHECK (intensity BETWEEN 1 AND 5),
    yielded      BOOLEAN NOT NULL DEFAULT FALSE,
    held_with    TEXT[],
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_wr_triggers_date ON war_room_triggers(date DESC);

CREATE TABLE IF NOT EXISTS war_room_arsenal (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    label        TEXT NOT NULL,
    category     TEXT NOT NULL DEFAULT 'other'
                   CHECK (category IN ('call','physical','breath','mental','environment','other')),
    use_count    INTEGER NOT NULL DEFAULT 0,
    last_used_at TIMESTAMPTZ,
    sort_order   INTEGER NOT NULL DEFAULT 0,
    active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- RLS: permissive (single-user app) — privacy enforced at API + iOS biometric layers
ALTER TABLE war_room_config   ENABLE ROW LEVEL SECURITY;
ALTER TABLE war_room_battles  ENABLE ROW LEVEL SECURITY;
ALTER TABLE war_room_triggers ENABLE ROW LEVEL SECURITY;
ALTER TABLE war_room_arsenal  ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS wr_config_allow_all   ON war_room_config;
DROP POLICY IF EXISTS wr_battles_allow_all  ON war_room_battles;
DROP POLICY IF EXISTS wr_triggers_allow_all ON war_room_triggers;
DROP POLICY IF EXISTS wr_arsenal_allow_all  ON war_room_arsenal;

CREATE POLICY wr_config_allow_all   ON war_room_config   FOR ALL TO anon USING (true);
CREATE POLICY wr_battles_allow_all  ON war_room_battles  FOR ALL TO anon USING (true);
CREATE POLICY wr_triggers_allow_all ON war_room_triggers FOR ALL TO anon USING (true);
CREATE POLICY wr_arsenal_allow_all  ON war_room_arsenal  FOR ALL TO anon USING (true);

