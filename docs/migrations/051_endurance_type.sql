-- Migration 051: type endurance pour exercices basés sur la durée (Plank, Deadhang)
-- Étend le CHECK load_profile pour inclure 'endurance', met à jour Plank,
-- et ajoute Deadhang au catalogue.

-- Étendre la contrainte CHECK existante
ALTER TABLE public.exercises
    DROP CONSTRAINT IF EXISTS exercises_load_profile_check;

ALTER TABLE public.exercises
    ADD CONSTRAINT exercises_load_profile_check
    CHECK (load_profile IN ('compound_heavy', 'compound_hypertrophy', 'isolation', 'endurance'));

-- S'assurer que tracking_type existe (créé en migration 001 mais ajouté ici en sécurité)
ALTER TABLE public.exercises
    ADD COLUMN IF NOT EXISTS tracking_type TEXT NOT NULL DEFAULT 'reps';

-- Migrer Plank vers le type endurance
UPDATE public.exercises
SET load_profile = 'endurance',
    tracking_type = 'time'
WHERE name = 'Plank';

-- Ajouter Deadhang au catalogue
INSERT INTO public.exercises (
    name, type, category, pattern, level,
    increment, default_scheme, tracking_type, load_profile,
    muscles, tips
)
VALUES (
    'Deadhang', 'bodyweight', 'grip', 'hang', 'intermediate',
    0.0, '3x45s', 'time', 'endurance',
    ARRAY['grip', 'forearms', 'lats'],
    'Épaules engagées, pas de shrug — tiens jusqu''à l''échec propre'
)
ON CONFLICT (name) DO UPDATE SET
    type          = EXCLUDED.type,
    category      = EXCLUDED.category,
    pattern       = EXCLUDED.pattern,
    level         = EXCLUDED.level,
    increment     = EXCLUDED.increment,
    default_scheme = EXCLUDED.default_scheme,
    tracking_type = EXCLUDED.tracking_type,
    load_profile  = EXCLUDED.load_profile,
    muscles       = EXCLUDED.muscles,
    tips          = EXCLUDED.tips,
    deleted_at    = NULL;
