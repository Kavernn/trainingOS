-- 094_op3_merge_neck_curl.sql
-- OP3 — Merge Neck Curl :
--   canon "Neck Curl"     = 10254163-84fd-4bd6-8187-132c40992e72   (7 logs, 4 pbe, 0 PR)
--   dup   "Neck curl"     = 610b92d0-f003-4f25-b6ad-eff39574112a   (1 log,  1 pbe, 0 PR)
--
-- Repoint des 6 FK cataloguées en 0a :
--   exercise_logs, program_block_exercises, exercise_prs,
--   educational_content, goals, session_plan_overrides
-- Aucune collision pbe (prouvé 0c). Aucune collision logs (prouvé 0d).
-- Aucune ligne PR côté dup (prouvé 0d).
-- Après repoint : soft-delete du dup (deleted_at = now()).
--
-- Idempotence :
--   - UPDATE ... WHERE exercise_id = dup → re-run = 0 row (déjà tout repointé).
--   - UPDATE exercises SET deleted_at=now() WHERE id=dup AND deleted_at IS NULL → re-run = 0 row.
--   - Garde AVANT accepte l'état PRE (dup vif) ET l'état POST (dup deleted, tout repointé)
--     via l'invariant de conservation (canon + dup = total constant).

BEGIN;

-- ===== Preuve [AVANT] : counts par table + deleted_at du dup =====
SELECT '[AVANT]' AS marker, 'exercise_logs'           AS ref_table, 'canon' AS role, COUNT(*)::bigint AS n
  FROM exercise_logs           WHERE exercise_id = '10254163-84fd-4bd6-8187-132c40992e72'
UNION ALL SELECT '[AVANT]', 'exercise_logs',           'dup',   COUNT(*) FROM exercise_logs           WHERE exercise_id = '610b92d0-f003-4f25-b6ad-eff39574112a'
UNION ALL SELECT '[AVANT]', 'program_block_exercises', 'canon', COUNT(*) FROM program_block_exercises WHERE exercise_id = '10254163-84fd-4bd6-8187-132c40992e72'
UNION ALL SELECT '[AVANT]', 'program_block_exercises', 'dup',   COUNT(*) FROM program_block_exercises WHERE exercise_id = '610b92d0-f003-4f25-b6ad-eff39574112a'
UNION ALL SELECT '[AVANT]', 'exercise_prs',            'canon', COUNT(*) FROM exercise_prs            WHERE exercise_id = '10254163-84fd-4bd6-8187-132c40992e72'
UNION ALL SELECT '[AVANT]', 'exercise_prs',            'dup',   COUNT(*) FROM exercise_prs            WHERE exercise_id = '610b92d0-f003-4f25-b6ad-eff39574112a'
UNION ALL SELECT '[AVANT]', 'educational_content',     'canon', COUNT(*) FROM educational_content     WHERE exercise_id = '10254163-84fd-4bd6-8187-132c40992e72'
UNION ALL SELECT '[AVANT]', 'educational_content',     'dup',   COUNT(*) FROM educational_content     WHERE exercise_id = '610b92d0-f003-4f25-b6ad-eff39574112a'
UNION ALL SELECT '[AVANT]', 'goals',                   'canon', COUNT(*) FROM goals                   WHERE exercise_id = '10254163-84fd-4bd6-8187-132c40992e72'
UNION ALL SELECT '[AVANT]', 'goals',                   'dup',   COUNT(*) FROM goals                   WHERE exercise_id = '610b92d0-f003-4f25-b6ad-eff39574112a'
UNION ALL SELECT '[AVANT]', 'session_plan_overrides',  'canon', COUNT(*) FROM session_plan_overrides  WHERE exercise_id = '10254163-84fd-4bd6-8187-132c40992e72'
UNION ALL SELECT '[AVANT]', 'session_plan_overrides',  'dup',   COUNT(*) FROM session_plan_overrides  WHERE exercise_id = '610b92d0-f003-4f25-b6ad-eff39574112a'
UNION ALL SELECT '[AVANT]', 'exercises.deleted_at',    'dup',
  CASE WHEN (SELECT deleted_at FROM exercises WHERE id='610b92d0-f003-4f25-b6ad-eff39574112a') IS NULL THEN 0 ELSE 1 END
ORDER BY ref_table, role;

-- ===== Garde AVANT — invariant de conservation vs diag Phase 1.5 =====
DO $$
DECLARE
  logs_canon INT; logs_dup INT;
  pbe_canon  INT; pbe_dup  INT;
  prs_dup    INT;
  canon_exists BOOLEAN;
  dup_exists   BOOLEAN;
BEGIN
  SELECT EXISTS(SELECT 1 FROM exercises WHERE id='10254163-84fd-4bd6-8187-132c40992e72') INTO canon_exists;
  SELECT EXISTS(SELECT 1 FROM exercises WHERE id='610b92d0-f003-4f25-b6ad-eff39574112a') INTO dup_exists;
  IF NOT canon_exists THEN RAISE EXCEPTION 'OP3 précondition: canon Neck Curl introuvable'; END IF;
  IF NOT dup_exists   THEN RAISE EXCEPTION 'OP3 précondition: dup Neck curl introuvable'; END IF;

  SELECT COUNT(*) INTO logs_canon FROM exercise_logs           WHERE exercise_id='10254163-84fd-4bd6-8187-132c40992e72';
  SELECT COUNT(*) INTO logs_dup   FROM exercise_logs           WHERE exercise_id='610b92d0-f003-4f25-b6ad-eff39574112a';
  SELECT COUNT(*) INTO pbe_canon  FROM program_block_exercises WHERE exercise_id='10254163-84fd-4bd6-8187-132c40992e72';
  SELECT COUNT(*) INTO pbe_dup    FROM program_block_exercises WHERE exercise_id='610b92d0-f003-4f25-b6ad-eff39574112a';
  SELECT COUNT(*) INTO prs_dup    FROM exercise_prs            WHERE exercise_id='610b92d0-f003-4f25-b6ad-eff39574112a';

  -- Assertions strictes UNIQUEMENT sur les tables mesurées par le diag Phase 1.5.
  -- Invariant de conservation (canon + dup constant) sur logs/pbe → tolère PRE et POST.
  IF (logs_canon + logs_dup) <> 8 THEN
    RAISE EXCEPTION 'OP3 précondition drift: exercise_logs total attendu 8, trouvé % (canon=%, dup=%)',
      logs_canon+logs_dup, logs_canon, logs_dup;
  END IF;
  IF (pbe_canon + pbe_dup) <> 5 THEN
    RAISE EXCEPTION 'OP3 précondition drift: program_block_exercises total attendu 5, trouvé % (canon=%, dup=%)',
      pbe_canon+pbe_dup, pbe_canon, pbe_dup;
  END IF;

  -- exercise_prs : le 0d prouvait dup=0. Le canon peut avoir >0 PR (upsert_exercise_pr
  -- après chaque log réussi) — c'est normal. Après repoint des logs vers canon, OP6
  -- (recompute_exercise_pr Python) rejouera l'e1RM sur l'ensemble fusionné.
  IF prs_dup <> 0 THEN
    RAISE EXCEPTION 'OP3 précondition drift: exercise_prs.dup attendu 0 (per 0d), trouvé %', prs_dup;
  END IF;

  -- edu/goals/spo : pas de mesure Phase 1.5. Aucune assertion pré-condition — les counts
  -- sont exposés dans la preuve [AVANT]/[APRÈS]. La garde APRÈS vérifie dup=0 partout.
END $$;

-- ===== Repoint des 6 FK (idempotent) =====
UPDATE exercise_logs           SET exercise_id='10254163-84fd-4bd6-8187-132c40992e72'
  WHERE exercise_id='610b92d0-f003-4f25-b6ad-eff39574112a';
UPDATE program_block_exercises SET exercise_id='10254163-84fd-4bd6-8187-132c40992e72'
  WHERE exercise_id='610b92d0-f003-4f25-b6ad-eff39574112a';
UPDATE exercise_prs            SET exercise_id='10254163-84fd-4bd6-8187-132c40992e72'
  WHERE exercise_id='610b92d0-f003-4f25-b6ad-eff39574112a';
UPDATE educational_content     SET exercise_id='10254163-84fd-4bd6-8187-132c40992e72'
  WHERE exercise_id='610b92d0-f003-4f25-b6ad-eff39574112a';
UPDATE goals                   SET exercise_id='10254163-84fd-4bd6-8187-132c40992e72'
  WHERE exercise_id='610b92d0-f003-4f25-b6ad-eff39574112a';
UPDATE session_plan_overrides  SET exercise_id='10254163-84fd-4bd6-8187-132c40992e72'
  WHERE exercise_id='610b92d0-f003-4f25-b6ad-eff39574112a';

-- ===== Soft-delete du dup (idempotent) =====
UPDATE exercises
SET    deleted_at = now()
WHERE  id='610b92d0-f003-4f25-b6ad-eff39574112a'
  AND  deleted_at IS NULL;

-- ===== Garde APRÈS — dup doit être orphelin =====
DO $$
DECLARE
  n INT;
  dup_deleted TIMESTAMPTZ;
BEGIN
  SELECT COUNT(*) INTO n FROM exercise_logs           WHERE exercise_id='610b92d0-f003-4f25-b6ad-eff39574112a';
  IF n<>0 THEN RAISE EXCEPTION 'OP3 post: exercise_logs dup devrait être 0, trouvé %', n; END IF;
  SELECT COUNT(*) INTO n FROM program_block_exercises WHERE exercise_id='610b92d0-f003-4f25-b6ad-eff39574112a';
  IF n<>0 THEN RAISE EXCEPTION 'OP3 post: program_block_exercises dup devrait être 0, trouvé %', n; END IF;
  SELECT COUNT(*) INTO n FROM exercise_prs            WHERE exercise_id='610b92d0-f003-4f25-b6ad-eff39574112a';
  IF n<>0 THEN RAISE EXCEPTION 'OP3 post: exercise_prs dup devrait être 0, trouvé %', n; END IF;
  SELECT COUNT(*) INTO n FROM educational_content     WHERE exercise_id='610b92d0-f003-4f25-b6ad-eff39574112a';
  IF n<>0 THEN RAISE EXCEPTION 'OP3 post: educational_content dup devrait être 0, trouvé %', n; END IF;
  SELECT COUNT(*) INTO n FROM goals                   WHERE exercise_id='610b92d0-f003-4f25-b6ad-eff39574112a';
  IF n<>0 THEN RAISE EXCEPTION 'OP3 post: goals dup devrait être 0, trouvé %', n; END IF;
  SELECT COUNT(*) INTO n FROM session_plan_overrides  WHERE exercise_id='610b92d0-f003-4f25-b6ad-eff39574112a';
  IF n<>0 THEN RAISE EXCEPTION 'OP3 post: session_plan_overrides dup devrait être 0, trouvé %', n; END IF;

  SELECT deleted_at INTO dup_deleted FROM exercises WHERE id='610b92d0-f003-4f25-b6ad-eff39574112a';
  IF dup_deleted IS NULL THEN
    RAISE EXCEPTION 'OP3 post: dup deleted_at devrait être NOT NULL, trouvé NULL';
  END IF;
END $$;

-- ===== Preuve [APRÈS] =====
SELECT '[APRÈS]' AS marker, 'exercise_logs'           AS ref_table, 'canon' AS role, COUNT(*)::bigint AS n
  FROM exercise_logs           WHERE exercise_id = '10254163-84fd-4bd6-8187-132c40992e72'
UNION ALL SELECT '[APRÈS]', 'exercise_logs',           'dup',   COUNT(*) FROM exercise_logs           WHERE exercise_id = '610b92d0-f003-4f25-b6ad-eff39574112a'
UNION ALL SELECT '[APRÈS]', 'program_block_exercises', 'canon', COUNT(*) FROM program_block_exercises WHERE exercise_id = '10254163-84fd-4bd6-8187-132c40992e72'
UNION ALL SELECT '[APRÈS]', 'program_block_exercises', 'dup',   COUNT(*) FROM program_block_exercises WHERE exercise_id = '610b92d0-f003-4f25-b6ad-eff39574112a'
UNION ALL SELECT '[APRÈS]', 'exercise_prs',            'canon', COUNT(*) FROM exercise_prs            WHERE exercise_id = '10254163-84fd-4bd6-8187-132c40992e72'
UNION ALL SELECT '[APRÈS]', 'exercise_prs',            'dup',   COUNT(*) FROM exercise_prs            WHERE exercise_id = '610b92d0-f003-4f25-b6ad-eff39574112a'
UNION ALL SELECT '[APRÈS]', 'educational_content',     'canon', COUNT(*) FROM educational_content     WHERE exercise_id = '10254163-84fd-4bd6-8187-132c40992e72'
UNION ALL SELECT '[APRÈS]', 'educational_content',     'dup',   COUNT(*) FROM educational_content     WHERE exercise_id = '610b92d0-f003-4f25-b6ad-eff39574112a'
UNION ALL SELECT '[APRÈS]', 'goals',                   'canon', COUNT(*) FROM goals                   WHERE exercise_id = '10254163-84fd-4bd6-8187-132c40992e72'
UNION ALL SELECT '[APRÈS]', 'goals',                   'dup',   COUNT(*) FROM goals                   WHERE exercise_id = '610b92d0-f003-4f25-b6ad-eff39574112a'
UNION ALL SELECT '[APRÈS]', 'session_plan_overrides',  'canon', COUNT(*) FROM session_plan_overrides  WHERE exercise_id = '10254163-84fd-4bd6-8187-132c40992e72'
UNION ALL SELECT '[APRÈS]', 'session_plan_overrides',  'dup',   COUNT(*) FROM session_plan_overrides  WHERE exercise_id = '610b92d0-f003-4f25-b6ad-eff39574112a'
UNION ALL SELECT '[APRÈS]', 'exercises.deleted_at',    'dup',
  CASE WHEN (SELECT deleted_at FROM exercises WHERE id='610b92d0-f003-4f25-b6ad-eff39574112a') IS NULL THEN 0 ELSE 1 END
ORDER BY ref_table, role;

COMMIT;
