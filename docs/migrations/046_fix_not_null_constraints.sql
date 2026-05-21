-- Migration 046 — Contraintes NOT NULL manquantes
--
-- Problème 1 : workout_sessions.session_name nullable
--   Sans valeur garantie, les analyses par type de séance (Upper A, Push, etc.)
--   retournent des résultats incomplets. Le coach IA ne peut pas matcher la séance
--   du jour si session_name = NULL.
--
-- Problème 2 : pss_records.type nullable
--   La contrainte UNIQUE(date, type) est inefficace si type = NULL
--   (NULL ≠ NULL en SQL → les doublons ne sont pas détectés).
--   Voir migration 025 qui a ajouté cette contrainte unique.
--
-- Pattern safe : UPDATE les lignes existantes avant d'appliquer NOT NULL.

-- ── workout_sessions ──────────────────────────────────────────────────────────
UPDATE workout_sessions
SET session_name = 'Séance'
WHERE session_name IS NULL;

ALTER TABLE workout_sessions
    ALTER COLUMN session_name SET NOT NULL,
    ALTER COLUMN session_name SET DEFAULT 'Séance';

-- ── pss_records ───────────────────────────────────────────────────────────────
UPDATE pss_records
SET type = 'full'
WHERE type IS NULL;

ALTER TABLE pss_records
    ALTER COLUMN type SET NOT NULL,
    ALTER COLUMN type SET DEFAULT 'full';

-- Marquer comme appliquée dans le tracker
INSERT INTO public.schema_migrations (version)
VALUES ('046_fix_not_null_constraints')
ON CONFLICT (version) DO NOTHING;
