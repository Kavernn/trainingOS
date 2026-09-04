-- 094_op2_plyo.sql
-- OP2 — Plyo: bascule 5 exos en tracking_type='plyo'.
--   Metadata uniquement, 0 FK touchée.
--
--   Les 4 déjà en movement_pattern='Plyometric' : tracking_type 'reps' → 'plyo'.
--     * Medicine Ball Overhead Throw
--     * Medicine Ball Chest Pass
--     * Barbell Jump Shrug
--     * Medicine Ball Slam
--
--   Le 5e (mp incohérent) : tracking_type 'reps' → 'plyo' ET movement_pattern 'Squat' → 'Plyometric'.
--     * Jump Squat
--
-- Idempotence : mutations conditionnées par état source (WHERE tracking_type='reps'
-- ou WHERE movement_pattern='Squat') → re-run = 0 row affectée, pas d'erreur.
-- Résolution des ids par name : la garde échoue si un name matche 0 ou >1 row
-- non soft-deletée.
-- CHECK constraint tracking_type accepte 'plyo' depuis migration 087a.

BEGIN;

-- Preuve AVANT
SELECT
  '[AVANT]' AS marker,
  id, name, tracking_type, movement_pattern
FROM exercises
WHERE name IN (
    'Medicine Ball Overhead Throw',
    'Medicine Ball Chest Pass',
    'Barbell Jump Shrug',
    'Medicine Ball Slam',
    'Jump Squat'
  )
  AND deleted_at IS NULL
ORDER BY name;

-- Garde de pré-condition
DO $$
DECLARE
  v_names_all   TEXT[] := ARRAY[
    'Medicine Ball Overhead Throw',
    'Medicine Ball Chest Pass',
    'Barbell Jump Shrug',
    'Medicine Ball Slam',
    'Jump Squat'
  ];
  v_names_group TEXT[] := ARRAY[
    'Medicine Ball Overhead Throw',
    'Medicine Ball Chest Pass',
    'Barbell Jump Shrug',
    'Medicine Ball Slam'
  ];
  v_name        TEXT;
  v_count       INT;
  v_tracking    TEXT;
  v_mp          TEXT;
BEGIN
  -- 1) résolution unique de chaque name (1 row non soft-deletée exactement)
  FOREACH v_name IN ARRAY v_names_all LOOP
    SELECT COUNT(*) INTO v_count
      FROM exercises
      WHERE name = v_name AND deleted_at IS NULL;

    IF v_count = 0 THEN
      RAISE EXCEPTION 'OP2 précondition: exercice ''%'' introuvable (0 row non soft-deletée)', v_name;
    ELSIF v_count > 1 THEN
      RAISE EXCEPTION 'OP2 précondition: exercice ''%'' ambigu (% rows non soft-deletées)', v_name, v_count;
    END IF;
  END LOOP;

  -- 2) état attendu des 4 (tracking = 'reps' avant migration, 'plyo' après = re-run)
  FOREACH v_name IN ARRAY v_names_group LOOP
    SELECT tracking_type INTO v_tracking
      FROM exercises
      WHERE name = v_name AND deleted_at IS NULL;

    IF v_tracking NOT IN ('reps', 'plyo') THEN
      RAISE EXCEPTION 'OP2 précondition: ''%'' tracking_type attendu ''reps'' ou ''plyo'', trouvé ''%''',
        v_name, v_tracking;
    END IF;
  END LOOP;

  -- 3) état attendu de Jump Squat (tracking + mp)
  SELECT tracking_type, movement_pattern INTO v_tracking, v_mp
    FROM exercises
    WHERE name = 'Jump Squat' AND deleted_at IS NULL;

  IF v_tracking NOT IN ('reps', 'plyo') THEN
    RAISE EXCEPTION 'OP2 précondition: ''Jump Squat'' tracking_type attendu ''reps'' ou ''plyo'', trouvé ''%''',
      v_tracking;
  END IF;
  IF v_mp NOT IN ('Squat', 'Plyometric') THEN
    RAISE EXCEPTION 'OP2 précondition: ''Jump Squat'' movement_pattern attendu ''Squat'' ou ''Plyometric'', trouvé ''%''',
      v_mp;
  END IF;
END $$;

-- Mutation 1 : tracking_type → 'plyo' pour les 5 (idempotent via WHERE = 'reps')
UPDATE exercises
SET    tracking_type = 'plyo'
WHERE  deleted_at IS NULL
  AND  tracking_type = 'reps'
  AND  name IN (
    'Medicine Ball Overhead Throw',
    'Medicine Ball Chest Pass',
    'Barbell Jump Shrug',
    'Medicine Ball Slam',
    'Jump Squat'
  );

-- Mutation 2 : Jump Squat mp 'Squat' → 'Plyometric' (idempotent via WHERE = 'Squat')
UPDATE exercises
SET    movement_pattern = 'Plyometric'
WHERE  deleted_at IS NULL
  AND  name = 'Jump Squat'
  AND  movement_pattern = 'Squat';

-- Preuve APRÈS
SELECT
  '[APRÈS]' AS marker,
  id, name, tracking_type, movement_pattern
FROM exercises
WHERE name IN (
    'Medicine Ball Overhead Throw',
    'Medicine Ball Chest Pass',
    'Barbell Jump Shrug',
    'Medicine Ball Slam',
    'Jump Squat'
  )
  AND deleted_at IS NULL
ORDER BY name;

COMMIT;
