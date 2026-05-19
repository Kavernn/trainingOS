-- Migration 038 — recovery_logs: add perceived fatigue column (Hooper Index)
-- Fatigue perçue (0-10) — quatrième dimension du Hooper Index (Hooper & Mackinnon, 1995)
-- Complète les trois dimensions existantes : sommeil, douleurs, stress/tension

ALTER TABLE recovery_logs ADD COLUMN IF NOT EXISTS fatigue_perceived SMALLINT;
