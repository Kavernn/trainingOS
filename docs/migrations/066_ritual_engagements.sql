-- Migration 066 — Engagements quotidiens
-- Nouveau flow rituel : N engagements créés le soir pour le lendemain, adressés fait/non-fait.
-- Table indépendante de daily_ritual — zéro impact sur l'historique existant.
-- date = jour CIBLE (lendemain au moment de la création, ex: créé le 8 juin → date = 9 juin)

CREATE TABLE IF NOT EXISTS ritual_engagements (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    date        DATE        NOT NULL,
    text        TEXT        NOT NULL,
    status      TEXT        CHECK (status IN ('done', 'notdone')),
    sort_order  INTEGER     NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ritual_engagements_date ON ritual_engagements (date DESC);

ALTER TABLE ritual_engagements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "allow_all" ON ritual_engagements
    FOR ALL USING (true) WITH CHECK (true);
