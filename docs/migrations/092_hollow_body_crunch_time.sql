-- 092_hollow_body_crunch_time.sql
-- Hollow Body Crunch : gainage isométrique 3x30s, mais tracking_type='reps'
-- → carte poids+reps au lieu du chronomètre EnduranceTimerSection.
-- Bascule vers 'time'. 2 logs reps historiques (juin/juillet 2026) restent tels
-- quels (vestige d'unité cosmétique, non migrés — zéro modif de l'historique).
-- 'time' autorisé par exercises_tracking_type_check (mig 087a).
-- Idempotent : le WHERE tracking_type='reps' rend un 2e run no-op.

UPDATE exercises
SET tracking_type = 'time'
WHERE name = 'Hollow Body Crunch' AND tracking_type = 'reps';
