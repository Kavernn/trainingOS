-- MIGRATION 087c — flag catalogue is_unilateral (2026-08-03)
--
-- Le modèle de modalité (Locked In 2027) prévoit is_unilateral comme flag catalogue
-- orthogonal au tracking_type. 087a a posé `side` sur exercise_logs (les LOGS) ;
-- 087c pose le flag sur le CATALOGUE (l'exo est-il unilatéral par nature).
-- Requis avant seed : Cable Woodchopper + Copenhagen / Side Plank sont unilatéraux.
-- Default FALSE → les 127 exos existants restent bilatéraux (safe, zéro impact).
-- Orthogonal au gate 087b : touche exercises, pas exercise_logs.

ALTER TABLE public.exercises
    ADD COLUMN IF NOT EXISTS is_unilateral BOOLEAN NOT NULL DEFAULT FALSE;
