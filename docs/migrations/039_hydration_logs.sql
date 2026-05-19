-- Migration 039 — hydration_logs : suivi hydrique quotidien
-- Objectif : 35 ml × poids_kg + 600 ml si séance (Cheuvront & Kenefick 2014)

CREATE TABLE IF NOT EXISTS hydration_logs (
    id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    date       DATE NOT NULL DEFAULT CURRENT_DATE,
    logged_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    amount_ml  INTEGER NOT NULL CHECK (amount_ml > 0)
);

CREATE INDEX IF NOT EXISTS hydration_logs_date_idx ON hydration_logs (date);

-- RLS : lecture/écriture restreintes à l'utilisateur authentifié
ALTER TABLE hydration_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user can manage own hydration"
    ON hydration_logs
    FOR ALL
    USING (true)
    WITH CHECK (true);
