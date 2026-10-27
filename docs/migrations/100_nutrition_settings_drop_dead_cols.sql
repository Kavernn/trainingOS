-- 100 — nutrition_settings : drop 6 colonnes mortes
-- Phase B2.8 : suivi glucides/lipides retiré (lots nutrition cleanup iOS/backend),
-- cible calorique = adaptative (compute_target_calories). Les 6 colonnes
-- ci-dessous n'ont plus aucun consommateur runtime en prod :
--
--   calorie_limit    — remplacée par compute_target_calories (TDEE 7j glissant)
--   day_type_targets — carte MacrosDayTypeView supprimée côté iOS, plus de resolve
--   glucides         — champ fixe legacy, zéro lecteur runtime
--   glucides_target  — doublon de glucides, zéro lecteur
--   lipides          — zéro lecteur
--   lipides_target   — doublon, zéro lecteur
--
-- Consommateurs résiduels neutralisés :
--   - api/readiness.py:306 lit settings.get("glucides_target") pour le score
--     fuel : fallback use_carbs=False lorsque target_carb=0 → scoring 50/50
--     cal/prot. Dégrade proprement, pas de crash.
--   - api/db_profile.py:89 défaut {calorie_limit: 2000} pour profil neuf —
--     retiré en lot séparé (bootstrap profile, inoffensif).
--
-- Table garde : id, protein_target, nutrition_end_time, updated_at.
-- RLS inchangée (policies anon_all/service_role_all préservées).

BEGIN;

ALTER TABLE public.nutrition_settings
    DROP COLUMN IF EXISTS calorie_limit,
    DROP COLUMN IF EXISTS day_type_targets,
    DROP COLUMN IF EXISTS glucides,
    DROP COLUMN IF EXISTS glucides_target,
    DROP COLUMN IF EXISTS lipides,
    DROP COLUMN IF EXISTS lipides_target;

COMMIT;
