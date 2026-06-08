-- Migration 063: classification anatomique et fonctionnelle des exercices
-- Ajoute 6 nouvelles colonnes nullable — zéro breaking change sur les données existantes
-- Auto-mappe muscle_group et weight_type depuis les colonnes existantes

-- 1. Nouvelles colonnes
ALTER TABLE public.exercises
    ADD COLUMN IF NOT EXISTS muscle_group      TEXT,           -- groupe principal (Pectoraux, Dos, ...)
    ADD COLUMN IF NOT EXISTS muscle_specific   TEXT,           -- muscle précis (Deltoïde postérieur, ...)
    ADD COLUMN IF NOT EXISTS secondary_muscles TEXT[],         -- muscles secondaires, max 3
    ADD COLUMN IF NOT EXISTS movement_pattern  TEXT,           -- pattern fonctionnel détaillé (17 valeurs)
    ADD COLUMN IF NOT EXISTS weight_type       TEXT,           -- type de calcul du poids (9 valeurs)
    ADD COLUMN IF NOT EXISTS equipment         TEXT[],         -- équipements multiples
    ADD COLUMN IF NOT EXISTS alternate_name    TEXT;           -- alias / surnom

-- 2. Auto-mapping weight_type depuis le champ type existant
UPDATE public.exercises SET weight_type = CASE type
    WHEN 'barbell'      THEN 'barbell'
    WHEN 'ez-bar'       THEN 'barbell'
    WHEN 'dumbbell'     THEN 'dumbbell'
    WHEN 'cable'        THEN 'cable_single'
    WHEN 'cable_double' THEN 'cable_double'
    WHEN 'machine'      THEN 'machine'
    WHEN 'bodyweight'   THEN 'bodyweight'
    ELSE NULL
END
WHERE type IS NOT NULL AND weight_type IS NULL;

-- 3. Auto-mapping tracking_type=time → weight_type endurance
UPDATE public.exercises SET weight_type = 'endurance'
WHERE tracking_type = 'time' AND (weight_type IS NULL OR weight_type = '');

-- 4. Auto-mapping muscle_group depuis muscles[]
-- Prend le premier muscle reconnu dans le tableau existant
UPDATE public.exercises SET muscle_group = CASE
    WHEN muscles && ARRAY['chest']                          THEN 'Pectoraux'
    WHEN muscles && ARRAY['back', 'lats', 'traps']         THEN 'Dos'
    WHEN muscles && ARRAY['shoulders', 'delts']            THEN 'Épaules'
    WHEN muscles && ARRAY['biceps', 'forearms']            THEN 'Biceps+Avant-bras'
    WHEN muscles && ARRAY['triceps']                       THEN 'Triceps'
    WHEN muscles && ARRAY['quads', 'quadriceps']           THEN 'Quadriceps'
    WHEN muscles && ARRAY['hamstrings']                    THEN 'Ischio-jambiers'
    WHEN muscles && ARRAY['glutes']                        THEN 'Fessiers'
    WHEN muscles && ARRAY['calves']                        THEN 'Mollets'
    WHEN muscles && ARRAY['core', 'abs']                   THEN 'Core'
    WHEN muscles && ARRAY['adductors', 'hip flexors']      THEN 'Hanches'
    ELSE NULL
END
WHERE array_length(muscles, 1) > 0 AND muscle_group IS NULL;
