-- Migration 044 — FK formelle mood_logs → pss_records
--
-- Problème : mood_logs.pss_score_linked est de type INT et représente le score PSS
-- dénormalisé (0–40) associé à l'entrée humeur. Il n'y a pas de lien formel vers
-- pss_records, ce qui empêche le JOIN garanti et crée un risque d'orphelins.
--
-- Décision :
--   - Garder pss_score_linked INT (valeur du score, rétrocompatibilité)
--   - Ajouter pss_record_id UUID avec FK formelle vers pss_records(id) ON DELETE SET NULL
--     pour les nouvelles entrées qui veulent lier à l'enregistrement PSS complet.
--
-- Le backend peut populer pss_record_id en même temps que pss_score_linked.

ALTER TABLE mood_logs
    ADD COLUMN IF NOT EXISTS pss_record_id UUID
        REFERENCES pss_records(id) ON DELETE SET NULL;

-- Marquer comme appliquée dans le tracker
INSERT INTO public.schema_migrations (version)
VALUES ('044_fix_mood_logs_pss_fk')
ON CONFLICT (version) DO NOTHING;
