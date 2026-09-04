-- 094_op0a_fks.sql — READ-ONLY
-- Énumération exhaustive des colonnes FK qui référencent exercises.id.
-- Source : information_schema (aucune hypothèse). Schéma public uniquement.

SELECT
  tc.table_name       AS ref_table,
  kcu.column_name     AS ref_column,
  tc.constraint_name,
  rc.delete_rule
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
 AND tc.table_schema    = kcu.table_schema
JOIN information_schema.constraint_column_usage ccu
  ON ccu.constraint_name = tc.constraint_name
 AND ccu.table_schema    = tc.table_schema
LEFT JOIN information_schema.referential_constraints rc
  ON rc.constraint_name  = tc.constraint_name
 AND rc.constraint_schema = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND ccu.table_name     = 'exercises'
  AND ccu.column_name    = 'id'
  AND tc.table_schema    = 'public'
ORDER BY ref_table, ref_column;
