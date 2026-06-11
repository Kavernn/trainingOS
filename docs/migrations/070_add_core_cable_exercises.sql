-- Migration 070: Pallof Press + Cable Crunch (catalogue core/câble)
INSERT INTO public.exercises (
    name, type, category, pattern, level, muscles, tips,
    increment, bar_weight, default_scheme, tracking_type,
    load_profile, muscle_group, muscle_specific, secondary_muscles,
    movement_pattern, weight_type, equipment, alternate_name, rest_seconds
) VALUES
(
    'Pallof Press', 'cable', 'strength', 'core', 'intermediate',
    ARRAY['core', 'obliques'],
    'Bras tendus devant, résistez à la rotation. Hanches neutres, core braced. Inspirez → tenue → expirez. 3x10 par côté.',
    2.5, 0, '3x10', 'reps',
    'isolation', 'Core', 'Obliques', ARRAY['Épaules'],
    'core', 'cable_single', ARRAY['câble'], 'Anti-Rotation Press', 75
),
(
    'Cable Crunch', 'cable', 'strength', 'core', 'beginner',
    ARRAY['core'],
    'À genoux, fléchissez la colonne (pas les hanches). Contraction maximale au bas. Coudes fixes.',
    2.5, 0, '3x12-15', 'reps',
    'isolation', 'Core', 'Abdominaux', ARRAY['Obliques'],
    'core', 'cable_double', ARRAY['câble'], 'Crunch Poulie', 60
)
ON CONFLICT (name) DO NOTHING;
