-- 093_plyo_exercises.sql
-- Box Jump / Broad Jump / Lateral Bound : sauts explosifs. tracking_type='reps'
-- → carte poids+reps, la hauteur/distance de saut ne se logge pas.
-- Bascule vers 'plyo' (déjà autorisé par exercises_tracking_type_check, 087a).
-- La saisie hauteur/distance via le champ intensity arrive aux étapes 2 (iOS)
-- et 3 (backend). Tant que l'iOS n'est pas déployé, 'plyo' retombe sur la carte
-- reps (fallback ExerciseCard else) — inoffensif.
-- Unité résolue par l'exo : Box Jump = cm (vertical), Broad/Lateral = m (horizontal).
-- Idempotent : WHERE tracking_type='reps' rend un 2e run no-op.
-- Logs reps historiques éventuels : laissés tels quels (zéro modif historique).

UPDATE exercises
SET tracking_type = 'plyo'
WHERE name IN ('Box Jump', 'Broad Jump', 'Lateral Bound')
  AND tracking_type = 'reps';
