-- 094_op0_preflight.sql
-- Pré-flight du nettoyage catalogue exercises (Phase 1.5 → merges).
-- READ-ONLY. Zéro écriture. À exécuter dans le SQL Editor Supabase.
--
-- Sections :
--   0a. Énumération des FK réelles pointant sur exercises.id (information_schema)
--   0b. État actuel des 3 paires (canonique ← dup) : logs + pbe, à comparer au diag Phase 1.5
--   0c. Collisions pbe : dup et canonique dans le MÊME block_id
--
-- Valeurs attendues (diag 2026-09-04) :
--   Pushdown     : canon fc506d23 (14 logs, 5 pbe) | dup 6f0a128f (16 logs, 2 pbe)
--   Neck Curl    : canon 10254163 ( 7 logs, 4 pbe) | dup 610b92d0 ( 1 log , 1 pbe)
--   Reverse Curl : canon b953ce24 (17 logs, 3 pbe) | dup 62d0bf52 ( 3 logs, 1 pbe)

-- ========================================================================
-- 0a. FK réelles vers exercises.id (source de vérité pour les repointages)
-- ========================================================================
SELECT
  tc.table_schema   AS ref_schema,
  tc.table_name     AS ref_table,
  kcu.column_name   AS ref_column,
  ccu.table_name    AS target_table,
  ccu.column_name   AS target_column,
  tc.constraint_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
 AND tc.table_schema    = kcu.table_schema
JOIN information_schema.constraint_column_usage ccu
  ON ccu.constraint_name = tc.constraint_name
 AND ccu.table_schema    = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND ccu.table_name     = 'exercises'
  AND ccu.column_name    = 'id'
  AND tc.table_schema    = 'public'
ORDER BY ref_table, ref_column;

-- ========================================================================
-- 0b. État actuel des 3 paires — assertion visuelle vs diag Phase 1.5
-- ========================================================================
WITH pairs(role, id, expected_name, expected_logs, expected_pbe) AS (
  VALUES
    ('canon (Pushdown)',     'fc506d23-f991-490a-8e46-37dc38461943'::uuid, 'Triceps Pushdown', 14, 5),
    ('dup   (Pushdown)',     '6f0a128f-d066-47b9-bcb8-dd3b798a232e'::uuid, 'Tricep Pushdown',  16, 2),
    ('canon (Neck Curl)',    '10254163-84fd-4bd6-8187-132c40992e72'::uuid, 'Neck Curl',         7, 4),
    ('dup   (Neck Curl)',    '610b92d0-f003-4f25-b6ad-eff39574112a'::uuid, 'Neck curl',         1, 1),
    ('canon (Reverse Curl)', 'b953ce24-0fe9-4180-ba98-919e90f99597'::uuid, 'Reverse curls',    17, 3),
    ('dup   (Reverse Curl)', '62d0bf52-3564-489d-b877-1fda69c6fce1'::uuid, 'Reverse Curl',      3, 1)
)
SELECT
  p.role,
  p.id                                                 AS id_expected,
  e.id                                                 AS id_found,
  p.expected_name                                      AS name_expected,
  e.name                                               AS name_found,
  e.deleted_at,
  p.expected_logs                                      AS logs_expected,
  (SELECT COUNT(*) FROM exercise_logs           WHERE exercise_id = p.id) AS logs_found,
  p.expected_pbe                                       AS pbe_expected,
  (SELECT COUNT(*) FROM program_block_exercises WHERE exercise_id = p.id) AS pbe_found,
  CASE
    WHEN e.id IS NULL THEN 'MISSING'
    WHEN e.deleted_at IS NOT NULL THEN 'ALREADY_DELETED'
    WHEN (SELECT COUNT(*) FROM exercise_logs           WHERE exercise_id = p.id) <> p.expected_logs
      OR (SELECT COUNT(*) FROM program_block_exercises WHERE exercise_id = p.id) <> p.expected_pbe
      THEN 'DRIFT'
    ELSE 'OK'
  END AS status
FROM pairs p
LEFT JOIN exercises e ON e.id = p.id
ORDER BY p.role;

-- ========================================================================
-- 0c. Collisions pbe : dup et canonique dans le MÊME block_id
--     → repoint interdit sur ces block_id (contrainte UNIQUE(block_id, exercise_id))
--     → à traiter par DELETE du pbe redondant du dup au lieu d'UPDATE
-- ========================================================================
WITH pairs(pair_name, canon_id, dup_id) AS (
  VALUES
    ('Pushdown',     'fc506d23-f991-490a-8e46-37dc38461943'::uuid, '6f0a128f-d066-47b9-bcb8-dd3b798a232e'::uuid),
    ('Neck Curl',    '10254163-84fd-4bd6-8187-132c40992e72'::uuid, '610b92d0-f003-4f25-b6ad-eff39574112a'::uuid),
    ('Reverse Curl', 'b953ce24-0fe9-4180-ba98-919e90f99597'::uuid, '62d0bf52-3564-489d-b877-1fda69c6fce1'::uuid)
)
SELECT
  p.pair_name,
  p.canon_id,
  p.dup_id,
  pbe_dup.block_id,
  pbe_dup.id       AS dup_pbe_id,
  pbe_dup.scheme   AS dup_scheme,
  pbe_canon.id     AS canon_pbe_id,
  pbe_canon.scheme AS canon_scheme
FROM pairs p
JOIN program_block_exercises pbe_dup   ON pbe_dup.exercise_id   = p.dup_id
JOIN program_block_exercises pbe_canon ON pbe_canon.exercise_id = p.canon_id
                                       AND pbe_canon.block_id   = pbe_dup.block_id
ORDER BY p.pair_name, pbe_dup.block_id;

-- Contre-preuve : si la requête ci-dessus retourne 0 ligne, aucune collision.
-- Total attendu (rappel) : 3+1+1 = 5 pbe côté dup à traiter au total, dont N en collision.

-- ========================================================================
-- 0d. exercise_logs qui violeraient l'UNIQUE (session_id, exercise_id, side)
--     après un repoint dup → canon (même side dans la même session, deux exos)
-- ========================================================================
WITH pairs(pair_name, canon_id, dup_id) AS (
  VALUES
    ('Pushdown',     'fc506d23-f991-490a-8e46-37dc38461943'::uuid, '6f0a128f-d066-47b9-bcb8-dd3b798a232e'::uuid),
    ('Neck Curl',    '10254163-84fd-4bd6-8187-132c40992e72'::uuid, '610b92d0-f003-4f25-b6ad-eff39574112a'::uuid),
    ('Reverse Curl', 'b953ce24-0fe9-4180-ba98-919e90f99597'::uuid, '62d0bf52-3564-489d-b877-1fda69c6fce1'::uuid)
)
SELECT
  p.pair_name,
  el_dup.session_id,
  el_dup.side,
  el_dup.id   AS dup_log_id,
  el_canon.id AS canon_log_id
FROM pairs p
JOIN exercise_logs el_dup   ON el_dup.exercise_id   = p.dup_id
JOIN exercise_logs el_canon ON el_canon.exercise_id = p.canon_id
                            AND el_canon.session_id  = el_dup.session_id
                            AND el_canon.side        = el_dup.side
ORDER BY p.pair_name, el_dup.session_id;

-- Si 0 ligne → repoint FK exercise_logs sûr (aucun conflit UNIQUE).
-- Si >0 → cas à trancher (les DEUX exos loggés dans la même séance côté même side).
