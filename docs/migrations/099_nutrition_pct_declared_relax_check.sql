-- 099 — nutrition_entries : élargit la plage CHECK des pct_declared à [0, 2.0]
-- Le curseur de rattrapage iOS (ContentView.swift L223/234) laisse l'utilisateur
-- aller jusqu'à 200 % des cibles. La contrainte initiale (098) à 1.5 bloquait
-- toute écriture au-dessus de 150 %. 2.0 reste strict (impossible de stocker
-- un ratio > 2 par accident côté client).

BEGIN;

ALTER TABLE public.nutrition_entries
    DROP CONSTRAINT nutrition_entries_pct_calories_range,
    DROP CONSTRAINT nutrition_entries_pct_proteines_range;

ALTER TABLE public.nutrition_entries
    ADD CONSTRAINT nutrition_entries_pct_calories_range
        CHECK (pct_calories_declared  IS NULL OR (pct_calories_declared  BETWEEN 0.0 AND 2.0)),
    ADD CONSTRAINT nutrition_entries_pct_proteines_range
        CHECK (pct_proteines_declared IS NULL OR (pct_proteines_declared BETWEEN 0.0 AND 2.0));

COMMIT;
