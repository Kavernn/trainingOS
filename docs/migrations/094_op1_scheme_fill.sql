-- 094_op1_scheme_fill.sql
-- OP1 — Scheme fill: Overhead Triceps Extension default_scheme NULL → '3x10-12'.
-- Metadata uniquement, 0 FK touchée.
--
-- Idempotence : WHERE default_scheme IS NULL → re-run = 0 row affectée, pas d'erreur.
-- Pré-condition : la row existe, non soft-deletée, scheme est NULL ou déjà '3x10-12'.
-- La transaction abort proprement (ROLLBACK auto) si l'état réel ≠ attendu.
--
-- NE PAS toucher 'Bloc plancher pelvien' (tracking_type=protocol, scheme='' correct).

BEGIN;

-- Preuve avant
SELECT
  '[AVANT]'                                       AS marker,
  id, name, default_scheme, tracking_type,
  deleted_at
FROM exercises
WHERE id = '79bd63ce-e625-4e18-a7cd-aee68cc6f3fe';

-- Garde de pré-condition
DO $$
DECLARE
  v_current  TEXT;
  v_deleted  TIMESTAMPTZ;
  v_exists   BOOLEAN;
BEGIN
  SELECT TRUE, default_scheme, deleted_at
    INTO v_exists, v_current, v_deleted
  FROM exercises
  WHERE id = '79bd63ce-e625-4e18-a7cd-aee68cc6f3fe';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'OP1 précondition: exercise 79bd63ce introuvable';
  END IF;
  IF v_deleted IS NOT NULL THEN
    RAISE EXCEPTION 'OP1 précondition: exercise 79bd63ce soft-deleted at % — abort',
      v_deleted;
  END IF;
  IF v_current IS NOT NULL AND v_current <> '3x10-12' THEN
    RAISE EXCEPTION 'OP1 précondition: default_scheme attendu NULL ou ''3x10-12'', trouvé ''%''',
      v_current;
  END IF;
END $$;

-- Mutation (idempotente)
UPDATE exercises
SET    default_scheme = '3x10-12'
WHERE  id = '79bd63ce-e625-4e18-a7cd-aee68cc6f3fe'
  AND  default_scheme IS NULL;

-- Preuve après
SELECT
  '[APRÈS]'                                       AS marker,
  id, name, default_scheme, tracking_type,
  deleted_at
FROM exercises
WHERE id = '79bd63ce-e625-4e18-a7cd-aee68cc6f3fe';

COMMIT;
