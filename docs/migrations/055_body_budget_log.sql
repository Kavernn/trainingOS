-- Migration 055 : Body Budget daily log — EMA 3j et calcul de tendance
-- Stocke le score brut et le score lissé par jour pour le lissage exponentiel
-- Zéro impact sur les tables existantes

CREATE TABLE IF NOT EXISTS body_budget_log (
  date           DATE        PRIMARY KEY,
  raw_score      INTEGER     NOT NULL,
  smoothed_score INTEGER     NOT NULL,
  training       INTEGER     NOT NULL,
  stress         INTEGER     NOT NULL,
  nutrition      INTEGER     NOT NULL,
  computed_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
