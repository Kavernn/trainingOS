-- Migration 104 — Fusion partition spirit dans technique_id + idempotence started_at
--
-- CONTEXTE : la table breathwork_sessions a deux partitions historiques
--   wellness : technique_id NOT NULL (catalogue 4 techniques)
--   spirit   : protocol NOT NULL (calm_storm, ignite, stillness)
-- Décision : une seule partition. Spirit calm_storm/stillness repliés sur
-- techniques du catalogue existant ('478', 'box'). Ignite abandonné (0 séance).
--
-- ORDRE : exécuter 104 AVANT le déploiement backend. La migration 105
-- (DROP COLUMN protocol) suit APRÈS le déploiement.
--
-- VÉRIFICATIONS PRÉALABLES (à lancer manuellement avant d'exécuter ce fichier) :
--   SELECT protocol, count(*) FROM breathwork_sessions
--     WHERE protocol IS NOT NULL GROUP BY 1;
--   -- attendu : calm_storm=1, stillness=2, aucun ignite. Si ignite > 0 → STOP.
--
--   SELECT count(*) FROM breathwork_sessions
--     WHERE technique_id IS NULL AND protocol IS NULL;
--   -- attendu : 0
--
--   SELECT started_at, count(*) FROM breathwork_sessions
--     GROUP BY 1 HAVING count(*) > 1;
--   -- attendu : 1 ligne (le backfill du 25 mai à started_at = '2026-05-25 18:53:29.680426+00')

-- 1. Fusion partition spirit → technique_id
--    calm_storm (4-7-8) ≡ catalogue '478'   (nom affiché : "4-7-8")
--    stillness  (box)   ≡ catalogue 'box'   (nom affiché : "Box Breathing")
UPDATE breathwork_sessions
  SET technique_id = CASE protocol
                       WHEN 'calm_storm' THEN '478'
                       WHEN 'stillness'  THEN 'box'
                     END,
      technique    = CASE protocol
                       WHEN 'calm_storm' THEN '4-7-8'
                       WHEN 'stillness'  THEN 'Box Breathing'
                     END
  WHERE protocol IN ('calm_storm', 'stillness') AND technique_id IS NULL;

-- 2. Correction du backfill du 25 mai (4 lignes avec started_at identique
--    — empêche la contrainte UNIQUE ci-dessous). Réaligne started_at sur logged_at.
UPDATE breathwork_sessions
  SET started_at = logged_at
  WHERE started_at = '2026-05-25 18:53:29.680426+00';

-- 3. Verrouillage : technique_id et started_at obligatoires
ALTER TABLE breathwork_sessions ALTER COLUMN technique_id SET NOT NULL;
ALTER TABLE breathwork_sessions ALTER COLUMN started_at   SET NOT NULL;

-- 4. Clé d'idempotence : started_at unique
ALTER TABLE breathwork_sessions
  ADD CONSTRAINT breathwork_sessions_started_at_key UNIQUE (started_at);
