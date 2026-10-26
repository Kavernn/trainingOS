-- 098 — nutrition_entries : traçabilité pct déclaré + cible historique
-- Contexte : les rattrapages (source=estimated_percent) stockaient uniquement
-- des calories/proteines calculées = pct × cible-du-moment, sans conserver ni
-- le pct déclaré par l'utilisateur ni la cible utilisée. Impossible à ce jour
-- de distinguer, dans l'historique, un déclaré "100 %" d'une surestimation
-- (incident 2026-10-15 à 2026-10-22 : cible gonflée par un chrono oublié,
-- rattrapages 100 % stockés tels quels sans signal utilisateur).
--
-- Historique : jours antérieurs à cette migration restent avec pct_* = NULL
-- (option A : exclus des % de conformité, comptés et affichés comme "N jours
-- estimés sans pourcentage enregistré").
--
-- Scale : pct_* en ratio [0.0, 1.0] (not 0-100). Plus propre, converti côté
-- écriture (replace_day_with_estimate) et côté slider iOS.
--
-- RLS : inchangée (table + policies existent déjà).
-- Pas de CREATE INDEX (table partielle PostgREST, pas de bénéfice ici).

BEGIN;

ALTER TABLE public.nutrition_entries
    ADD COLUMN pct_calories_declared     DOUBLE PRECISION,
    ADD COLUMN pct_proteines_declared    DOUBLE PRECISION,
    ADD COLUMN target_calories_snapshot  INTEGER,
    ADD COLUMN target_proteines_snapshot INTEGER;

-- Bornes sanity : si on écrit, c'est dans [0, 1.5] (marge pour > 100 %
-- légitime si l'utilisateur mange au-dessus de sa cible). NULL reste valide
-- (option A pour l'historique).
ALTER TABLE public.nutrition_entries
    ADD CONSTRAINT nutrition_entries_pct_calories_range
        CHECK (pct_calories_declared  IS NULL OR (pct_calories_declared  BETWEEN 0.0 AND 1.5)),
    ADD CONSTRAINT nutrition_entries_pct_proteines_range
        CHECK (pct_proteines_declared IS NULL OR (pct_proteines_declared BETWEEN 0.0 AND 1.5)),
    ADD CONSTRAINT nutrition_entries_target_calories_snapshot_positive
        CHECK (target_calories_snapshot  IS NULL OR target_calories_snapshot  > 0),
    ADD CONSTRAINT nutrition_entries_target_proteines_snapshot_positive
        CHECK (target_proteines_snapshot IS NULL OR target_proteines_snapshot > 0);

-- Backfill ciblé : 7 jours 2026-10-16 → 22 corrigés après fix duration
-- séance 2026-10-15 (chrono oublié). Ratio confirmé = 1.0 (cal stockées
-- avant correction = cible gonflée du moment). Target snapshots = valeurs
-- recalculées utilisées pour l'UPDATE calories.
-- Protéines : pct/snapshot laissés à NULL (ratio pas inférable — target
-- proteines variait selon day_type sans trace).
UPDATE public.nutrition_entries SET pct_calories_declared = 1.0, target_calories_snapshot = 2907 WHERE date = '2026-10-16' AND source = 'estimated_percent';
UPDATE public.nutrition_entries SET pct_calories_declared = 1.0, target_calories_snapshot = 2865 WHERE date = '2026-10-17' AND source = 'estimated_percent';
UPDATE public.nutrition_entries SET pct_calories_declared = 1.0, target_calories_snapshot = 2856 WHERE date = '2026-10-18' AND source = 'estimated_percent';
UPDATE public.nutrition_entries SET pct_calories_declared = 1.0, target_calories_snapshot = 2913 WHERE date = '2026-10-19' AND source = 'estimated_percent';
UPDATE public.nutrition_entries SET pct_calories_declared = 1.0, target_calories_snapshot = 2962 WHERE date = '2026-10-20' AND source = 'estimated_percent';
UPDATE public.nutrition_entries SET pct_calories_declared = 1.0, target_calories_snapshot = 2916 WHERE date = '2026-10-21' AND source = 'estimated_percent';
UPDATE public.nutrition_entries SET pct_calories_declared = 1.0, target_calories_snapshot = 2937 WHERE date = '2026-10-22' AND source = 'estimated_percent';

COMMIT;
