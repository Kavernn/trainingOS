-- 091_resurrect_neck_extension.sql
-- Neck Extension soft-deleted le 2026-08-04 alors que GymProgramme v4 le
-- référence (Push B PM, Finition). Ligne catalogue propre (Cou / Splénius /
-- bodyweight / push_vertical) — ressuscitation plutôt que doublon.
-- Idempotent : le WHERE deleted_at IS NOT NULL rend un 2e run inoffensif (0 ligne).
-- N'affecte QUE la ligne 'Neck Extension'. Ne touche pas 'Neck curl' (doublon
-- NULL minuscule) ni aucune autre ligne — hors périmètre (carnet de ménage).

UPDATE exercises
SET deleted_at = NULL
WHERE name = 'Neck Extension' AND deleted_at IS NOT NULL;
