-- 094_op5_merge_pushdown.sql
-- OP5 — Merge Pushdown (le plus gros) :
--   canon "Triceps Pushdown" = fc506d23-f991-490a-8e46-37dc38461943  (14 logs, 5 pbe, 1 PR — e1rm 203.5)
--   dup   "Tricep Pushdown"  = 6f0a128f-d066-47b9-bcb8-dd3b798a232e  (16 logs, 2 pbe, 1 PR — e1rm 187.2)
--
-- Traitement identique à OP4 :
--   - DELETE la ligne PR du dup AVANT le repoint FK (résout collision UNIQUE(exercise_id)).
--   - Le canon garde son PR stale (203.5). OP6 recomputera sur logs fusionnés.
--   - Le PR dup (187.2) inférieur au canon → aucune information perdue par le DELETE.
--
-- 6 FK cataloguées (0a). Aucune collision pbe/logs (0c/0d).
--
-- Idempotence :
--   - Garde AVANT accepte prs_dup ∈ {0,1}, logs_canon+dup constant, pbe_canon+dup constant.
--   - DELETE + UPDATEs + soft-delete tous conditionnés → re-run = 0 row.
--
-- Preuve : DEUX SELECTs (avant/après) + RAISE NOTICE redondants pour garantir la visibilité
--          des valeurs [AVANT] même si le SQL Editor n'affiche qu'un onglet de résultat.

BEGIN;

-- ===== SELECT [AVANT] — premier tableau (13 lignes) =====
SELECT marker, ref_table, role, n FROM (
  SELECT '[AVANT]' AS marker, 'exercise_logs'           AS ref_table, 'canon' AS role, COUNT(*)::bigint AS n
    FROM exercise_logs           WHERE exercise_id='fc506d23-f991-490a-8e46-37dc38461943'
  UNION ALL SELECT '[AVANT]', 'exercise_logs',           'dup',   COUNT(*) FROM exercise_logs           WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e'
  UNION ALL SELECT '[AVANT]', 'program_block_exercises', 'canon', COUNT(*) FROM program_block_exercises WHERE exercise_id='fc506d23-f991-490a-8e46-37dc38461943'
  UNION ALL SELECT '[AVANT]', 'program_block_exercises', 'dup',   COUNT(*) FROM program_block_exercises WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e'
  UNION ALL SELECT '[AVANT]', 'exercise_prs',            'canon', COUNT(*) FROM exercise_prs            WHERE exercise_id='fc506d23-f991-490a-8e46-37dc38461943'
  UNION ALL SELECT '[AVANT]', 'exercise_prs',            'dup',   COUNT(*) FROM exercise_prs            WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e'
  UNION ALL SELECT '[AVANT]', 'educational_content',     'canon', COUNT(*) FROM educational_content     WHERE exercise_id='fc506d23-f991-490a-8e46-37dc38461943'
  UNION ALL SELECT '[AVANT]', 'educational_content',     'dup',   COUNT(*) FROM educational_content     WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e'
  UNION ALL SELECT '[AVANT]', 'goals',                   'canon', COUNT(*) FROM goals                   WHERE exercise_id='fc506d23-f991-490a-8e46-37dc38461943'
  UNION ALL SELECT '[AVANT]', 'goals',                   'dup',   COUNT(*) FROM goals                   WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e'
  UNION ALL SELECT '[AVANT]', 'session_plan_overrides',  'canon', COUNT(*) FROM session_plan_overrides  WHERE exercise_id='fc506d23-f991-490a-8e46-37dc38461943'
  UNION ALL SELECT '[AVANT]', 'session_plan_overrides',  'dup',   COUNT(*) FROM session_plan_overrides  WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e'
  UNION ALL SELECT '[AVANT]', 'exercises.deleted_at',    'dup',
    CASE WHEN (SELECT deleted_at FROM exercises WHERE id='6f0a128f-d066-47b9-bcb8-dd3b798a232e') IS NULL THEN 0 ELSE 1 END
) proof_before
ORDER BY ref_table, role;

-- ===== Garde AVANT — invariants Phase 1.5 + LOG [AVANT] via NOTICE (visibilité redondante) =====
DO $$
DECLARE
  logs_canon INT; logs_dup INT;
  pbe_canon  INT; pbe_dup  INT;
  prs_canon  INT; prs_dup  INT;
  edu_canon  INT; edu_dup  INT;
  gls_canon  INT; gls_dup  INT;
  spo_canon  INT; spo_dup  INT;
  dup_deleted TIMESTAMPTZ;
  canon_exists BOOLEAN; dup_exists BOOLEAN;
BEGIN
  SELECT EXISTS(SELECT 1 FROM exercises WHERE id='fc506d23-f991-490a-8e46-37dc38461943') INTO canon_exists;
  SELECT EXISTS(SELECT 1 FROM exercises WHERE id='6f0a128f-d066-47b9-bcb8-dd3b798a232e') INTO dup_exists;
  IF NOT canon_exists THEN RAISE EXCEPTION 'OP5 précondition: canon Triceps Pushdown introuvable'; END IF;
  IF NOT dup_exists   THEN RAISE EXCEPTION 'OP5 précondition: dup Tricep Pushdown introuvable'; END IF;

  SELECT COUNT(*) INTO logs_canon FROM exercise_logs           WHERE exercise_id='fc506d23-f991-490a-8e46-37dc38461943';
  SELECT COUNT(*) INTO logs_dup   FROM exercise_logs           WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e';
  SELECT COUNT(*) INTO pbe_canon  FROM program_block_exercises WHERE exercise_id='fc506d23-f991-490a-8e46-37dc38461943';
  SELECT COUNT(*) INTO pbe_dup    FROM program_block_exercises WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e';
  SELECT COUNT(*) INTO prs_canon  FROM exercise_prs            WHERE exercise_id='fc506d23-f991-490a-8e46-37dc38461943';
  SELECT COUNT(*) INTO prs_dup    FROM exercise_prs            WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e';
  SELECT COUNT(*) INTO edu_canon  FROM educational_content     WHERE exercise_id='fc506d23-f991-490a-8e46-37dc38461943';
  SELECT COUNT(*) INTO edu_dup    FROM educational_content     WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e';
  SELECT COUNT(*) INTO gls_canon  FROM goals                   WHERE exercise_id='fc506d23-f991-490a-8e46-37dc38461943';
  SELECT COUNT(*) INTO gls_dup    FROM goals                   WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e';
  SELECT COUNT(*) INTO spo_canon  FROM session_plan_overrides  WHERE exercise_id='fc506d23-f991-490a-8e46-37dc38461943';
  SELECT COUNT(*) INTO spo_dup    FROM session_plan_overrides  WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e';
  SELECT deleted_at INTO dup_deleted FROM exercises WHERE id='6f0a128f-d066-47b9-bcb8-dd3b798a232e';

  RAISE NOTICE 'OP5 [AVANT] logs canon=% dup=%  pbe canon=% dup=%  prs canon=% dup=%  edu canon=% dup=%  goals canon=% dup=%  spo canon=% dup=%  dup.deleted_at=%',
    logs_canon, logs_dup, pbe_canon, pbe_dup, prs_canon, prs_dup,
    edu_canon, edu_dup, gls_canon, gls_dup, spo_canon, spo_dup,
    COALESCE(dup_deleted::TEXT, 'NULL');

  -- Invariants stricts Phase 1.5 (conservation canon + dup)
  IF (logs_canon + logs_dup) <> 30 THEN
    RAISE EXCEPTION 'OP5 précondition drift: exercise_logs total attendu 30, trouvé % (canon=%, dup=%)',
      logs_canon+logs_dup, logs_canon, logs_dup;
  END IF;
  IF (pbe_canon + pbe_dup) <> 7 THEN
    RAISE EXCEPTION 'OP5 précondition drift: program_block_exercises total attendu 7, trouvé % (canon=%, dup=%)',
      pbe_canon+pbe_dup, pbe_canon, pbe_dup;
  END IF;

  -- exercise_prs : canon toujours 1 (upsert_exercise_pr après chaque log).
  -- dup PRE=1 (0d), POST=0 (après DELETE de re-run). Assertion accepte les deux.
  IF prs_canon <> 1 THEN
    RAISE EXCEPTION 'OP5 précondition drift: exercise_prs.canon attendu 1, trouvé %', prs_canon;
  END IF;
  IF prs_dup NOT IN (0, 1) THEN
    RAISE EXCEPTION 'OP5 précondition drift: exercise_prs.dup attendu 0 ou 1, trouvé %', prs_dup;
  END IF;

  -- edu/goals/spo : pas de mesure Phase 1.5. Aucune assertion pré. La garde APRÈS
  -- vérifie dup=0 partout après repoint (invariant fort).
END $$;

-- ===== DELETE PR du dup AVANT repoint (résout collision UNIQUE(exercise_id)) =====
DELETE FROM exercise_prs
WHERE exercise_id = '6f0a128f-d066-47b9-bcb8-dd3b798a232e';

-- ===== Repoint des 6 FK (idempotents) =====
UPDATE exercise_logs           SET exercise_id='fc506d23-f991-490a-8e46-37dc38461943'
  WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e';
UPDATE program_block_exercises SET exercise_id='fc506d23-f991-490a-8e46-37dc38461943'
  WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e';
UPDATE exercise_prs            SET exercise_id='fc506d23-f991-490a-8e46-37dc38461943'
  WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e';  -- no-op après DELETE
UPDATE educational_content     SET exercise_id='fc506d23-f991-490a-8e46-37dc38461943'
  WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e';
UPDATE goals                   SET exercise_id='fc506d23-f991-490a-8e46-37dc38461943'
  WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e';
UPDATE session_plan_overrides  SET exercise_id='fc506d23-f991-490a-8e46-37dc38461943'
  WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e';

-- ===== Soft-delete du dup (idempotent) =====
UPDATE exercises
SET    deleted_at = now()
WHERE  id='6f0a128f-d066-47b9-bcb8-dd3b798a232e'
  AND  deleted_at IS NULL;

-- ===== Garde APRÈS — dup orphelin partout + LOG [APRÈS] via NOTICE =====
DO $$
DECLARE
  logs_canon INT; logs_dup INT;
  pbe_canon  INT; pbe_dup  INT;
  prs_canon  INT; prs_dup  INT;
  edu_canon  INT; edu_dup  INT;
  gls_canon  INT; gls_dup  INT;
  spo_canon  INT; spo_dup  INT;
  dup_deleted TIMESTAMPTZ;
BEGIN
  SELECT COUNT(*) INTO logs_canon FROM exercise_logs           WHERE exercise_id='fc506d23-f991-490a-8e46-37dc38461943';
  SELECT COUNT(*) INTO logs_dup   FROM exercise_logs           WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e';
  SELECT COUNT(*) INTO pbe_canon  FROM program_block_exercises WHERE exercise_id='fc506d23-f991-490a-8e46-37dc38461943';
  SELECT COUNT(*) INTO pbe_dup    FROM program_block_exercises WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e';
  SELECT COUNT(*) INTO prs_canon  FROM exercise_prs            WHERE exercise_id='fc506d23-f991-490a-8e46-37dc38461943';
  SELECT COUNT(*) INTO prs_dup    FROM exercise_prs            WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e';
  SELECT COUNT(*) INTO edu_canon  FROM educational_content     WHERE exercise_id='fc506d23-f991-490a-8e46-37dc38461943';
  SELECT COUNT(*) INTO edu_dup    FROM educational_content     WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e';
  SELECT COUNT(*) INTO gls_canon  FROM goals                   WHERE exercise_id='fc506d23-f991-490a-8e46-37dc38461943';
  SELECT COUNT(*) INTO gls_dup    FROM goals                   WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e';
  SELECT COUNT(*) INTO spo_canon  FROM session_plan_overrides  WHERE exercise_id='fc506d23-f991-490a-8e46-37dc38461943';
  SELECT COUNT(*) INTO spo_dup    FROM session_plan_overrides  WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e';
  SELECT deleted_at INTO dup_deleted FROM exercises WHERE id='6f0a128f-d066-47b9-bcb8-dd3b798a232e';

  RAISE NOTICE 'OP5 [APRÈS] logs canon=% dup=%  pbe canon=% dup=%  prs canon=% dup=%  edu canon=% dup=%  goals canon=% dup=%  spo canon=% dup=%  dup.deleted_at=%',
    logs_canon, logs_dup, pbe_canon, pbe_dup, prs_canon, prs_dup,
    edu_canon, edu_dup, gls_canon, gls_dup, spo_canon, spo_dup,
    COALESCE(dup_deleted::TEXT, 'NULL');

  IF logs_dup <> 0 THEN RAISE EXCEPTION 'OP5 post: exercise_logs dup devrait être 0, trouvé %', logs_dup; END IF;
  IF pbe_dup  <> 0 THEN RAISE EXCEPTION 'OP5 post: program_block_exercises dup devrait être 0, trouvé %', pbe_dup; END IF;
  IF prs_dup  <> 0 THEN RAISE EXCEPTION 'OP5 post: exercise_prs dup devrait être 0, trouvé %', prs_dup; END IF;
  IF edu_dup  <> 0 THEN RAISE EXCEPTION 'OP5 post: educational_content dup devrait être 0, trouvé %', edu_dup; END IF;
  IF gls_dup  <> 0 THEN RAISE EXCEPTION 'OP5 post: goals dup devrait être 0, trouvé %', gls_dup; END IF;
  IF spo_dup  <> 0 THEN RAISE EXCEPTION 'OP5 post: session_plan_overrides dup devrait être 0, trouvé %', spo_dup; END IF;
  IF prs_canon <> 1 THEN RAISE EXCEPTION 'OP5 post: exercise_prs canon devrait être 1, trouvé %', prs_canon; END IF;
  IF dup_deleted IS NULL THEN RAISE EXCEPTION 'OP5 post: dup deleted_at devrait être NOT NULL'; END IF;
END $$;

-- ===== SELECT [APRÈS] — deuxième tableau =====
SELECT marker, ref_table, role, n FROM (
  SELECT '[APRÈS]' AS marker, 'exercise_logs'           AS ref_table, 'canon' AS role, COUNT(*)::bigint AS n
    FROM exercise_logs           WHERE exercise_id='fc506d23-f991-490a-8e46-37dc38461943'
  UNION ALL SELECT '[APRÈS]', 'exercise_logs',           'dup',   COUNT(*) FROM exercise_logs           WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e'
  UNION ALL SELECT '[APRÈS]', 'program_block_exercises', 'canon', COUNT(*) FROM program_block_exercises WHERE exercise_id='fc506d23-f991-490a-8e46-37dc38461943'
  UNION ALL SELECT '[APRÈS]', 'program_block_exercises', 'dup',   COUNT(*) FROM program_block_exercises WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e'
  UNION ALL SELECT '[APRÈS]', 'exercise_prs',            'canon', COUNT(*) FROM exercise_prs            WHERE exercise_id='fc506d23-f991-490a-8e46-37dc38461943'
  UNION ALL SELECT '[APRÈS]', 'exercise_prs',            'dup',   COUNT(*) FROM exercise_prs            WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e'
  UNION ALL SELECT '[APRÈS]', 'educational_content',     'canon', COUNT(*) FROM educational_content     WHERE exercise_id='fc506d23-f991-490a-8e46-37dc38461943'
  UNION ALL SELECT '[APRÈS]', 'educational_content',     'dup',   COUNT(*) FROM educational_content     WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e'
  UNION ALL SELECT '[APRÈS]', 'goals',                   'canon', COUNT(*) FROM goals                   WHERE exercise_id='fc506d23-f991-490a-8e46-37dc38461943'
  UNION ALL SELECT '[APRÈS]', 'goals',                   'dup',   COUNT(*) FROM goals                   WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e'
  UNION ALL SELECT '[APRÈS]', 'session_plan_overrides',  'canon', COUNT(*) FROM session_plan_overrides  WHERE exercise_id='fc506d23-f991-490a-8e46-37dc38461943'
  UNION ALL SELECT '[APRÈS]', 'session_plan_overrides',  'dup',   COUNT(*) FROM session_plan_overrides  WHERE exercise_id='6f0a128f-d066-47b9-bcb8-dd3b798a232e'
  UNION ALL SELECT '[APRÈS]', 'exercises.deleted_at',    'dup',
    CASE WHEN (SELECT deleted_at FROM exercises WHERE id='6f0a128f-d066-47b9-bcb8-dd3b798a232e') IS NULL THEN 0 ELSE 1 END
) proof_after
ORDER BY ref_table, role;

COMMIT;
