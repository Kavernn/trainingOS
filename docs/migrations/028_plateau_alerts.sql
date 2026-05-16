-- 028_plateau_alerts.sql
-- Plateau detection & deload recommendation alerts

CREATE TABLE IF NOT EXISTS plateau_alerts (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    detected_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    exercise_name    TEXT        NOT NULL,
    plateau_score    INTEGER     NOT NULL,
    plateau_weeks    INTEGER     NOT NULL,
    root_cause       TEXT        NOT NULL,
    severity         TEXT        NOT NULL CHECK (severity IN ('advisory', 'warning', 'critical')),
    deload_type      TEXT        CHECK (deload_type IN ('rest', 'light_week', 'rep_range', 'nutrition_first')),
    deload_plan      JSONB,
    rebound_days_min INTEGER,
    rebound_days_max INTEGER,
    status           TEXT        NOT NULL DEFAULT 'pending'
                                 CHECK (status IN ('pending', 'accepted', 'active', 'completed', 'dismissed')),
    dismissed_at     TIMESTAMPTZ,
    completed_at     TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_plateau_alerts_exercise ON plateau_alerts (exercise_name);
CREATE INDEX IF NOT EXISTS idx_plateau_alerts_status   ON plateau_alerts (status);
CREATE INDEX IF NOT EXISTS idx_plateau_alerts_detected ON plateau_alerts (detected_at DESC);

ALTER TABLE plateau_alerts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "allow_all_plateau_alerts" ON plateau_alerts FOR ALL USING (true) WITH CHECK (true);
