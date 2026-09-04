-- 094_op4_merge_reverse_curl.sql
-- OP4 — Merge Reverse Curl :
--   canon "Reverse curls"  = b953ce24-0fe9-4180-ba98-919e90f99597  (17 logs, 3 pbe, 1 PR)
--   dup   "Reverse Curl"   = 62d0bf52-3564-489d-b877-1fda69c6fce1  ( 3 logs, 1 pbe, 1 PR)
--
-- Cas spécial exercise_prs : les deux ont un PR (collision UNIQUE(exercise_id)).
-- On DELETE la ligne PR du dup AVANT le repoint FK. Le canon garde sa ligne PR
-- (stale après merge — recompute_exercise_pr('Reverse curls') en OP6 lissera).
--
-- 6 FK cataloguées (0a) : exercise_logs, program_block_exercises, exercise_prs,
--                         educational_content, goals, session_plan_overrides.
-- Aucune collision pbe/logs (0c/0d).
--
-- Idempotence :
--   - Garde AVANT accepte prs_dup ∈ {0,1} (0 = re-run après DELETE).
--   - DELETE + UPDATE conditionnés par exercise_id=dup → re-run = 0 row.
--   - Soft-delete conditionné par deleted_at IS NULL → re-run = 0 row.
-- Preuve : temp table capture les counts AVANT, SELECT final UNION ALL → un seul tableau.

BEGIN;

-- ===== SELECT [AVANT] — premier tableau =====
SELECT marker, ref_table, role, n FROM (
  SELECT '[AVANT]' AS marker, 'exercise_logs'           AS ref_table, 'canon' AS role, COUNT(*)::bigint AS n
    FROM exercise_logs           WHERE exercise_id='b953ce24-0fe9-4180-ba98-919e90f99597'
  UNION ALL SELECT '[AVANT]', 'exercise_logs',           'dup',   COUNT(*) FROM exercise_logs           WHERE exercise_id='62d0bf52-3564-489d-b877-1fda69c6fce1'
  UNION ALL SELECT '[AVANT]', 'program_block_exercises', 'canon', COUNT(*) FROM program_block_exercises WHERE exercise_id='b953ce24-0fe9-4180-ba98-919e90f99597'
  UNION ALL SELECT '[AVANT]', 'program_block_exercises', 'dup',   COUNT(*) FROM program_block_exercises WHERE exercise_id='62d0bf52-3564-489d-b877-1fda69c6fce1'
  UNION ALL SELECT '[AVANT]', 'exercise_prs',            'canon', COUNT(*) FROM exercise_prs            WHERE exercise_id='b953ce24-0fe9-4180-ba98-919e90f99597'
  UNION ALL SELECT '[AVANT]', 'exercise_prs',            'dup',   COUNT(*) FROM exercise_prs            WHERE exercise_id='62d0bf52-3564-489d-b877-1fda69c6fce1'
  UNION ALL SELECT '[AVANT]', 'educational_content',     'canon', COUNT(*) FROM educational_content     WHERE exercise_id='b953ce24-0fe9-4180-ba98-919e90f99597'
  UNION ALL SELECT '[AVANT]', 'educational_content',     'dup',   COUNT(*) FROM educational_content     WHERE exercise_id='62d0bf52-3564-489d-b877-1fda69c6fce1'
  UNION ALL SELECT '[AVANT]', 'goals',                   'canon', COUNT(*) FROM goals                   WHERE exercise_id='b953ce24-0fe9-4180-ba98-919e90f99597'
  UNION ALL SELECT '[AVANT]', 'goals',                   'dup',   COUNT(*) FROM goals                   WHERE exercise_id='62d0bf52-3564-489d-b877-1fda69c6fce1'
  UNION ALL SELECT '[AVANT]', 'session_plan_overrides',  'canon', COUNT(*) FROM session_plan_overrides  WHERE exercise_id='b953ce24-0fe9-4180-ba98-919e90f99597'
  UNION ALL SELECT '[AVANT]', 'session_plan_overrides',  'dup',   COUNT(*) FROM session_plan_overrides  WHERE exercise_id='62d0bf52-3564-489d-b877-1fda69c6fce1'
  UNION ALL SELECT '[AVANT]', 'exercises.deleted_at',    'dup',
    CASE WHEN (SELECT deleted_at FROM exercises WHERE id='62d0bf52-3564-489d-b877-1fda69c6fce1') IS NULL THEN 0 ELSE 1 END
) proof_before
ORDER BY ref_table, role;

-- ===== Garde AVANT — invariants Phase 1.5 =====
DO $$
DECLARE
  logs_canon INT; logs_dup INT;
  pbe_canon  INT; pbe_dup  INT;
  prs_canon  INT; prs_dup  INT;
  canon_exists BOOLEAN; dup_exists BOOLEAN;
BEGIN
  SELECT EXISTS(SELECT 1 FROM exercises WHERE id='b953ce24-0fe9-4180-ba98-919e90f99597') INTO canon_exists;
  SELECT EXISTS(SELECT 1 FROM exercises WHERE id='62d0bf52-3564-489d-b877-1fda69c6fce1') INTO dup_exists;
  IF NOT canon_exists THEN RAISE EXCEPTION 'OP4 précondition: canon Reverse curls introuvable'; END IF;
  IF NOT dup_exists   THEN RAISE EXCEPTION 'OP4 précondition: dup Reverse Curl introuvable'; END IF;

  SELECT COUNT(*) INTO logs_canon FROM exercise_logs           WHERE exercise_id='b953ce24-0fe9-4180-ba98-919e90f99597';
  SELECT COUNT(*) INTO logs_dup   FROM exercise_logs           WHERE exercise_id='62d0bf52-3564-489d-b877-1fda69c6fce1';
  SELECT COUNT(*) INTO pbe_canon  FROM program_block_exercises WHERE exercise_id='b953ce24-0fe9-4180-ba98-919e90f99597';
  SELECT COUNT(*) INTO pbe_dup    FROM program_block_exercises WHERE exercise_id='62d0bf52-3564-489d-b877-1fda69c6fce1';
  SELECT COUNT(*) INTO prs_canon  FROM exercise_prs            WHERE exercise_id='b953ce24-0fe9-4180-ba98-919e90f99597';
  SELECT COUNT(*) INTO prs_dup    FROM exercise_prs            WHERE exercise_id='62d0bf52-3564-489d-b877-1fda69c6fce1';

  -- logs/pbe : invariant de conservation (canon + dup constant) tolère PRE et POST.
  IF (logs_canon + logs_dup) <> 20 THEN
    RAISE EXCEPTION 'OP4 précondition drift: exercise_logs total attendu 20, trouvé % (canon=%, dup=%)',
      logs_canon+logs_dup, logs_canon, logs_dup;
  END IF;
  IF (pbe_canon + pbe_dup) <> 4 THEN
    RAISE EXCEPTION 'OP4 précondition drift: program_block_exercises total attendu 4, trouvé % (canon=%, dup=%)',
      pbe_canon+pbe_dup, pbe_canon, pbe_dup;
  END IF;

  -- exercise_prs : canon a toujours 1 PR (upsert_exercise_pr après chaque log).
  -- dup PRE = 1 (0d), POST = 0 (après DELETE de re-run). L'assertion accepte les deux.
  IF prs_canon <> 1 THEN
    RAISE EXCEPTION 'OP4 précondition drift: exercise_prs.canon attendu 1, trouvé %', prs_canon;
  END IF;
  IF prs_dup NOT IN (0, 1) THEN
    RAISE EXCEPTION 'OP4 précondition drift: exercise_prs.dup attendu 0 ou 1, trouvé %', prs_dup;
  END IF;

  -- edu/goals/spo : aucune assertion AVANT (jamais mesurés).
  -- Garde APRÈS vérifie dup=0 partout.
END $$;

-- ===== DELETE PR du dup AVANT repoint (résout collision UNIQUE(exercise_id)) =====
DELETE FROM exercise_prs
WHERE exercise_id = '62d0bf52-3564-489d-b877-1fda69c6fce1';

-- ===== Repoint des 6 FK (idempotents) =====
UPDATE exercise_logs           SET exercise_id='b953ce24-0fe9-4180-ba98-919e90f99597'
  WHERE exercise_id='62d0bf52-3564-489d-b877-1fda69c6fce1';
UPDATE program_block_exercises SET exercise_id='b953ce24-0fe9-4180-ba98-919e90f99597'
  WHERE exercise_id='62d0bf52-3564-489d-b877-1fda69c6fce1';
UPDATE exercise_prs            SET exercise_id='b953ce24-0fe9-4180-ba98-919e90f99597'
  WHERE exercise_id='62d0bf52-3564-489d-b877-1fda69c6fce1';  -- no-op après DELETE
UPDATE educational_content     SET exercise_id='b953ce24-0fe9-4180-ba98-919e90f99597'
  WHERE exercise_id='62d0bf52-3564-489d-b877-1fda69c6fce1';
UPDATE goals                   SET exercise_id='b953ce24-0fe9-4180-ba98-919e90f99597'
  WHERE exercise_id='62d0bf52-3564-489d-b877-1fda69c6fce1';
UPDATE session_plan_overrides  SET exercise_id='b953ce24-0fe9-4180-ba98-919e90f99597'
  WHERE exercise_id='62d0bf52-3564-489d-b877-1fda69c6fce1';

-- ===== Soft-delete du dup (idempotent) =====
UPDATE exercises
SET    deleted_at = now()
WHERE  id='62d0bf52-3564-489d-b877-1fda69c6fce1'
  AND  deleted_at IS NULL;

-- ===== Garde APRÈS — dup doit être orphelin partout =====
DO $$
DECLARE
  n INT;
  dup_deleted TIMESTAMPTZ;
BEGIN
  SELECT COUNT(*) INTO n FROM exercise_logs           WHERE exercise_id='62d0bf52-3564-489d-b877-1fda69c6fce1';
  IF n<>0 THEN RAISE EXCEPTION 'OP4 post: exercise_logs dup devrait être 0, trouvé %', n; END IF;
  SELECT COUNT(*) INTO n FROM program_block_exercises WHERE exercise_id='62d0bf52-3564-489d-b877-1fda69c6fce1';
  IF n<>0 THEN RAISE EXCEPTION 'OP4 post: program_block_exercises dup devrait être 0, trouvé %', n; END IF;
  SELECT COUNT(*) INTO n FROM exercise_prs            WHERE exercise_id='62d0bf52-3564-489d-b877-1fda69c6fce1';
  IF n<>0 THEN RAISE EXCEPTION 'OP4 post: exercise_prs dup devrait être 0, trouvé %', n; END IF;
  SELECT COUNT(*) INTO n FROM educational_content     WHERE exercise_id='62d0bf52-3564-489d-b877-1fda69c6fce1';
  IF n<>0 THEN RAISE EXCEPTION 'OP4 post: educational_content dup devrait être 0, trouvé %', n; END IF;
  SELECT COUNT(*) INTO n FROM goals                   WHERE exercise_id='62d0bf52-3564-489d-b877-1fda69c6fce1';
  IF n<>0 THEN RAISE EXCEPTION 'OP4 post: goals dup devrait être 0, trouvé %', n; END IF;
  SELECT COUNT(*) INTO n FROM session_plan_overrides  WHERE exercise_id='62d0bf52-3564-489d-b877-1fda69c6fce1';
  IF n<>0 THEN RAISE EXCEPTION 'OP4 post: session_plan_overrides dup devrait être 0, trouvé %', n; END IF;

  SELECT deleted_at INTO dup_deleted FROM exercises WHERE id='62d0bf52-3564-489d-b877-1fda69c6fce1';
  IF dup_deleted IS NULL THEN
    RAISE EXCEPTION 'OP4 post: dup deleted_at devrait être NOT NULL, trouvé NULL';
  END IF;

  -- Vérification canon PR : doit rester à 1 (celui du canon, stale mais présent).
  SELECT COUNT(*) INTO n FROM exercise_prs WHERE exercise_id='b953ce24-0fe9-4180-ba98-919e90f99597';
  IF n<>1 THEN RAISE EXCEPTION 'OP4 post: exercise_prs canon devrait être 1, trouvé %', n; END IF;
END $$;

-- ===== SELECT [APRÈS] — deuxième tableau =====
SELECT marker, ref_table, role, n FROM (
  SELECT '[APRÈS]' AS marker, 'exercise_logs'           AS ref_table, 'canon' AS role, COUNT(*)::bigint AS n
    FROM exercise_logs           WHERE exercise_id='b953ce24-0fe9-4180-ba98-919e90f99597'
  UNION ALL SELECT '[APRÈS]', 'exercise_logs',           'dup',   COUNT(*) FROM exercise_logs           WHERE exercise_id='62d0bf52-3564-489d-b877-1fda69c6fce1'
  UNION ALL SELECT '[APRÈS]', 'program_block_exercises', 'canon', COUNT(*) FROM program_block_exercises WHERE exercise_id='b953ce24-0fe9-4180-ba98-919e90f99597'
  UNION ALL SELECT '[APRÈS]', 'program_block_exercises', 'dup',   COUNT(*) FROM program_block_exercises WHERE exercise_id='62d0bf52-3564-489d-b877-1fda69c6fce1'
  UNION ALL SELECT '[APRÈS]', 'exercise_prs',            'canon', COUNT(*) FROM exercise_prs            WHERE exercise_id='b953ce24-0fe9-4180-ba98-919e90f99597'
  UNION ALL SELECT '[APRÈS]', 'exercise_prs',            'dup',   COUNT(*) FROM exercise_prs            WHERE exercise_id='62d0bf52-3564-489d-b877-1fda69c6fce1'
  UNION ALL SELECT '[APRÈS]', 'educational_content',     'canon', COUNT(*) FROM educational_content     WHERE exercise_id='b953ce24-0fe9-4180-ba98-919e90f99597'
  UNION ALL SELECT '[APRÈS]', 'educational_content',     'dup',   COUNT(*) FROM educational_content     WHERE exercise_id='62d0bf52-3564-489d-b877-1fda69c6fce1'
  UNION ALL SELECT '[APRÈS]', 'goals',                   'canon', COUNT(*) FROM goals                   WHERE exercise_id='b953ce24-0fe9-4180-ba98-919e90f99597'
  UNION ALL SELECT '[APRÈS]', 'goals',                   'dup',   COUNT(*) FROM goals                   WHERE exercise_id='62d0bf52-3564-489d-b877-1fda69c6fce1'
  UNION ALL SELECT '[APRÈS]', 'session_plan_overrides',  'canon', COUNT(*) FROM session_plan_overrides  WHERE exercise_id='b953ce24-0fe9-4180-ba98-919e90f99597'
  UNION ALL SELECT '[APRÈS]', 'session_plan_overrides',  'dup',   COUNT(*) FROM session_plan_overrides  WHERE exercise_id='62d0bf52-3564-489d-b877-1fda69c6fce1'
  UNION ALL SELECT '[APRÈS]', 'exercises.deleted_at',    'dup',
    CASE WHEN (SELECT deleted_at FROM exercises WHERE id='62d0bf52-3564-489d-b877-1fda69c6fce1') IS NULL THEN 0 ELSE 1 END
) proof_after
ORDER BY ref_table, role;

COMMIT;
