-- 083 : daily_brief — cache aligné sur le contrat single-user.
--
-- Contexte : migration 072 avait posé UNIQUE(user_id, date) + user_id NOT NULL
-- + policy auth.uid() (design multi-user), alors que le backend TrainingOS est
-- service_role single-user et n'a jamais fourni user_id dans l'upsert. Résultat
-- prouvé au log Vercel 18/07 : POST daily_brief?on_conflict=date → 42P10, GET
-- → 406 avalé en warning. Le cache n'a jamais fait un hit depuis la création.
--
-- Vérification préalable exécutée avant cette migration :
--   SELECT COUNT(*) FROM daily_brief; → 0 (table vierge, cohérent avec le bug).
--   Aucun doublon à traiter, pas de DELETE nécessaire.
--
-- Filet de sécurité : si un doublon apparaissait malgré tout, ADD CONSTRAINT
-- UNIQUE(date) ci-dessous échouerait atomiquement (rollback complet).

ALTER TABLE daily_brief DROP CONSTRAINT IF EXISTS daily_brief_user_id_date_key;
ALTER TABLE daily_brief ADD  CONSTRAINT daily_brief_date_key UNIQUE (date);
ALTER TABLE daily_brief ALTER COLUMN user_id DROP NOT NULL;

DROP POLICY IF EXISTS "daily_brief_self" ON daily_brief;
CREATE POLICY "daily_brief_anon_all"    ON daily_brief FOR ALL TO anon         USING (true) WITH CHECK (true);
CREATE POLICY "daily_brief_service_all" ON daily_brief FOR ALL TO service_role USING (true) WITH CHECK (true);
