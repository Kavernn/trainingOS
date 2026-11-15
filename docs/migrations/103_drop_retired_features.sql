-- 103 : DROP des tables orphelines après retrait des features dormantes.
--
-- Contexte : ménage novembre 2026. Les tables ci-dessous ne sont plus lues
-- ni écrites par le code (iOS + backend) depuis les commits 8fbf9230..4dcef0a6.
--
-- Vérification préalable à exécuter AVANT d'appliquer cette migration :
--   SELECT 'smart_alarm_sessions',      COUNT(*) FROM smart_alarm_sessions UNION ALL
--   SELECT 'hydration_logs',            COUNT(*) FROM hydration_logs UNION ALL
--   SELECT 'user_profile_backup_20260902', COUNT(*) FROM user_profile_backup_20260902 UNION ALL
--   SELECT 'coach_history',             COUNT(*) FROM coach_history UNION ALL
--   SELECT 'daily_brief',               COUNT(*) FROM daily_brief UNION ALL
--   SELECT 'time_capsules',             COUNT(*) FROM time_capsules UNION ALL
--   SELECT 'food_catalog',              COUNT(*) FROM food_catalog UNION ALL
--   SELECT 'smart_goals',               COUNT(*) FROM smart_goals UNION ALL
--   SELECT 'goals_archived',            COUNT(*) FROM goals_archived UNION ALL
--   SELECT 'body_budget_log',           COUNT(*) FROM body_budget_log UNION ALL
--   SELECT 'meal_templates',            COUNT(*) FROM meal_templates;
--
-- Les tables qui contiennent encore des lignes (ex. coach_history 306,
-- smart_alarm_sessions N) sont droppées malgré tout — Vince a décidé de ne
-- pas exporter (coach_history) ou les données n'ont pas de valeur analytique
-- (hydration_logs, smart_alarm_sessions).
--
-- Rollback : pas de restore automatique. En cas de regret, relire les CREATE
-- TABLE historiques dans docs/schema.sql et les migrations 030..055.

DROP TABLE IF EXISTS smart_alarm_sessions         CASCADE;
DROP TABLE IF EXISTS hydration_logs               CASCADE;
DROP TABLE IF EXISTS user_profile_backup_20260902 CASCADE;
DROP TABLE IF EXISTS coach_history                CASCADE;
DROP TABLE IF EXISTS daily_brief                  CASCADE;
DROP TABLE IF EXISTS time_capsules                CASCADE;
DROP TABLE IF EXISTS food_catalog                 CASCADE;
DROP TABLE IF EXISTS smart_goals                  CASCADE;
DROP TABLE IF EXISTS goals_archived               CASCADE;
DROP TABLE IF EXISTS body_budget_log              CASCADE;
DROP TABLE IF EXISTS meal_templates               CASCADE;
