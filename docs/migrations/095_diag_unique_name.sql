-- 095_diag_unique_name.sql — READ-ONLY
-- Vérifier la contrainte UNIQUE réelle sur exercises.name (avant Diff 1).
--
-- Questions :
-- 1. UNIQUE plein sur name ? partial index (WHERE deleted_at IS NULL) ? composite ?
-- 2. Case-sensitive ? (Neck Curl vs Neck curl coexistent — pourquoi ?)

-- === 1) Contraintes de table (pk + unique + check) ===
SELECT
  tc.constraint_name,
  tc.constraint_type,
  kcu.column_name,
  kcu.ordinal_position
FROM information_schema.table_constraints tc
LEFT JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
 AND tc.table_schema    = kcu.table_schema
WHERE tc.table_schema = 'public'
  AND tc.table_name   = 'exercises'
  AND tc.constraint_type IN ('PRIMARY KEY', 'UNIQUE')
ORDER BY tc.constraint_name, kcu.ordinal_position;

-- === 2) Index sur exercises.name (inclut les index partiels non déclarés en constraint) ===
SELECT
  i.indexname,
  i.indexdef,
  ix.indisunique,
  ix.indisprimary,
  pg_get_expr(ix.indpred, ix.indrelid) AS partial_where
FROM pg_indexes i
JOIN pg_class     c   ON c.relname = i.indexname
JOIN pg_index     ix  ON ix.indexrelid = c.oid
WHERE i.schemaname = 'public'
  AND i.tablename  = 'exercises'
ORDER BY i.indexname;

-- === 3) Preuve empirique de la coexistence "Neck Curl" + "Neck curl" ===
SELECT id, name, deleted_at,
       length(name)    AS len,
       octet_length(name) AS bytes
FROM exercises
WHERE lower(name) = 'neck curl'
ORDER BY name;
