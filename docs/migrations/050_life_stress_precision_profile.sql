-- Migration 050 — Ajouter precision_profile à life_stress_scores
--
-- La colonne precision_profile est calculée par life_stress_engine._precision_profile()
-- et stockée pour traçabilité de la qualité de donnée par date.
-- L'upsert échouait avec PGRST204 car la colonne n'existait pas.

ALTER TABLE life_stress_scores
    ADD COLUMN IF NOT EXISTS precision_profile TEXT;

INSERT INTO public.schema_migrations (version)
VALUES ('050_life_stress_precision_profile')
ON CONFLICT (version) DO NOTHING;
