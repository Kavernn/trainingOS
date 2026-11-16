-- Migration 106 — Idempotence meditation_sessions (clé started_at)
--
-- CONTEXTE : POST /api/spirit/meditation passe par offlinePost (iOS). Avant
-- cette migration, started_at = DEFAULT now() côté serveur et aucune
-- contrainte UNIQUE (033_spirit.sql:19, 059 = index non unique) → chaque
-- replay créait une ligne de plus, datée du replay. Le client fournit
-- désormais started_at (capturé au lancement de la séance) ; le backend fait
-- upsert(on_conflict="started_at", ignore_duplicates=True) + relecture.
-- Modèle : 104_breathwork_fusion.sql.
--
-- ORDRE : exécuter 106 AVANT le déploiement backend (sinon l'upsert
-- on_conflict="started_at" échoue : pas de contrainte correspondante).
--
-- VÉRIFICATIONS PRÉALABLES (à lancer manuellement avant d'exécuter ce fichier) :
--   SELECT conname, contype, pg_get_constraintdef(oid)
--     FROM pg_constraint
--     WHERE conrelid = 'public.meditation_sessions'::regclass;
--   -- attendu : 1 ligne, meditation_sessions_pkey (p). Si une UNIQUE existe déjà → STOP.
--
--   SELECT started_at, count(*) FROM meditation_sessions
--     GROUP BY 1 HAVING count(*) > 1;
--   -- attendu : 0 ligne. Sinon → STOP (doublons à arbitrer, aucune donnée historique modifiée ici).
--
--   SELECT count(*) FROM meditation_sessions;
--   -- attendu : 1 (séance du 2026-05-29). Données historiques NON modifiées.

ALTER TABLE meditation_sessions
  ADD CONSTRAINT meditation_sessions_started_at_key UNIQUE (started_at);

-- VÉRIFICATION POST-MIGRATION :
--   SELECT conname, pg_get_constraintdef(oid)
--     FROM pg_constraint
--     WHERE conrelid = 'public.meditation_sessions'::regclass AND contype = 'u';
--   -- attendu : meditation_sessions_started_at_key | UNIQUE (started_at)
