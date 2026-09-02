-- Migration 094 : tracking_type 'mobility' — rappels visuels sans log
--
-- CONTEXTE : les exos de mobilité (stretch, CARs, wall slides, band pull-apart)
-- sont des rappels "fais-le", pas des séries à mesurer. Nouveau mode iOS
-- ExerciseCard.isCheckOnly : nom + rappel + case à cocher. État local à la
-- séance, aucun log en base (exclus de exercise_logs, volume, stats). Étend le
-- vocabulaire fermé CHECK défini en migration 087a.
--
-- BACKUP tracking_type avant UPDATE (à restaurer si rollback) :
--   World's Greatest Stretch             : time
--   90/90 Hip + Band Shoulder Rotation   : time
--   Cat-Cow + Thoracic Rotation          : time
--   Thoracic Extension + Open Book       : reps
--   Band Shoulder CARs                   : time
--   Wall Slides                          : reps
--   Band Pull-Apart                      : reps

-- 1. Élargir le vocabulaire CHECK
ALTER TABLE exercises
    DROP CONSTRAINT IF EXISTS exercises_tracking_type_check;

ALTER TABLE exercises
    ADD CONSTRAINT exercises_tracking_type_check
    CHECK (tracking_type IN ('reps','time','carry','plyo','cardio','interval','protocol','mobility'));

-- 2. Retag des 7 exos de mobilité (idempotent : re-run = no-op si déjà 'mobility')
UPDATE exercises SET tracking_type = 'mobility'
WHERE name IN (
    'World''s Greatest Stretch',
    '90/90 Hip + Band Shoulder Rotation',
    'Cat-Cow + Thoracic Rotation',
    'Thoracic Extension + Open Book',
    'Band Shoulder CARs',
    'Wall Slides',
    'Band Pull-Apart'
) AND deleted_at IS NULL;

-- Preuve attendue : 7 rows updated (SELECT count(*) doit rendre 7)
-- SELECT name, tracking_type FROM exercises
-- WHERE tracking_type = 'mobility' AND deleted_at IS NULL ORDER BY name;
