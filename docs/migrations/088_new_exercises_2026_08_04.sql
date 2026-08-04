-- MIGRATION 088 — 10 nouveaux exos catalogue (2026-08-04)
--
-- Intégration programme "locked in" : ajout des fiches pour
-- Weighted Dips, Skull Crusher (EZ), Cable Pullover, Nordic Hamstring Curl,
-- Cable External Rotation, Prone Y-T-W Raises, Tibialis Raises, Wrist Roller,
-- Cossack Squat, Cable Curl.
--
-- ON CONFLICT (name) DO NOTHING : préserve les fiches existantes si un nom
-- collision déjà (ne réécrit pas les tips/schemes déjà personnalisés).
-- Le rattachement au programme se fait en étape séparée (schedule + POST /api/programme).

INSERT INTO public.exercises (
    name, type, category, pattern, level, default_scheme,
    muscles, increment, bar_weight, tracking_type, rest_seconds, tips,
    muscle_group, muscle_specific, secondary_muscles, movement_pattern,
    weight_type, equipment, is_unilateral
) VALUES
    (
        'Weighted Dips', 'bodyweight', 'push', 'push_horizontal', 'intermediate', '4x6-10',
        ARRAY['lower_chest','triceps','front_delts'], 2.5, 0, 'reps', 150,
        'Torse légèrement penché avant, épaules loin des oreilles, descente contrôlée.',
        'chest', 'lower_chest', ARRAY['triceps','front_delts'], 'push_horizontal',
        'strength', ARRAY['dip_bars','weight_belt'], FALSE
    ),
    (
        'Skull Crusher (EZ)', 'ez_bar', 'push', 'push_horizontal', 'intermediate', '4x8-12',
        ARRAY['triceps_long','triceps_lateral','triceps_medial'], 2.5, 15, 'reps', 120,
        'Coudes fixes vers plafond, barre au front puis au-dessus de la tête (extension complète).',
        'arms', 'triceps_long', ARRAY['triceps_lateral','triceps_medial'], 'push_horizontal',
        'strength', ARRAY['ez_bar','bench'], FALSE
    ),
    (
        'Cable Pullover', 'cable', 'pull', 'pull_vertical', 'intermediate', '3x12-15',
        ARRAY['lats','teres_major','chest_long'], 2.5, 0, 'reps', 90,
        'Bras quasi tendus, hanches en léger recul, tire avec les lats, pas les triceps.',
        'back', 'lats', ARRAY['teres_major','chest_long'], 'pull_vertical',
        'hypertrophy', ARRAY['cable','rope'], FALSE
    ),
    (
        'Nordic Hamstring Curl', 'bodyweight', 'legs', 'hinge', 'advanced', '3x6-8',
        ARRAY['hamstrings','glutes','calves'], 0, 0, 'reps', 180,
        'Éccentrique lent (3-5 s), rattrape avec les mains, remonte avec les bras.',
        'legs', 'hamstrings', ARRAY['glutes','calves'], 'hinge',
        'strength', ARRAY['nordic_bench','partner'], FALSE
    ),
    (
        'Cable External Rotation', 'cable', 'shoulders', 'rotation', 'intermediate', '3x15-20',
        ARRAY['rotator_cuff','rear_delts'], 2.5, 0, 'reps', 60,
        'Coude collé au flanc, avant-bras horizontal, rotation externe pure — pas d''épaule.',
        'shoulders', 'rotator_cuff', ARRAY['rear_delts'], 'rotation',
        'hypertrophy', ARRAY['cable','handle'], TRUE
    ),
    (
        'Prone Y-T-W Raises', 'dumbbell', 'back', 'pull_horizontal', 'beginner', '2x10',
        ARRAY['mid_traps','rear_delts','rhomboids'], 1, 0, 'reps', 60,
        'Bench incliné 30°, pouces vers le plafond, mouvement piloté par les omoplates.',
        'back', 'mid_traps', ARRAY['rear_delts','rhomboids'], 'pull_horizontal',
        'hypertrophy', ARRAY['incline_bench','light_dumbbells'], FALSE
    ),
    (
        'Tibialis Raises', 'bodyweight', 'legs', 'isolation', 'beginner', '2x15-20',
        ARRAY['tibialis_anterior'], 0, 0, 'reps', 60,
        'Dos au mur, talons décollés, remonte les orteils vers les tibias — brûle vite.',
        'legs', 'tibialis_anterior', ARRAY[]::text[], 'isolation',
        'endurance', ARRAY['wall'], FALSE
    ),
    (
        'Wrist Roller', 'specialty', 'arms', 'rotation', 'intermediate', '3x30-60s',
        ARRAY['forearms','grip'], 2.5, 0, 'time', 90,
        'Bras tendus à hauteur d''épaule, roule complètement en haut, descente contrôlée. 3 allers-retours OU 3×30-60 s.',
        'arms', 'forearms', ARRAY['grip'], 'rotation',
        'endurance', ARRAY['wrist_roller'], FALSE
    ),
    (
        'Cossack Squat', 'bodyweight', 'legs', 'lunge', 'beginner', '2x6',
        ARRAY['adductors','quads','glutes'], 0, 0, 'reps', 60,
        'Talons au sol, jambe tendue orteils au plafond, torse droit, descente profonde.',
        'legs', 'adductors', ARRAY['quads','glutes'], 'lunge',
        'mobility', ARRAY[]::text[], TRUE
    ),
    (
        'Cable Curl', 'cable', 'pull', 'pull_vertical', 'intermediate', '3x10-12',
        ARRAY['biceps_short','brachialis','forearms'], 2.5, 0, 'reps', 90,
        'Coudes collés au corps, pas de balancement, contraction pic en haut.',
        'arms', 'biceps_short', ARRAY['brachialis','forearms'], 'pull_vertical',
        'hypertrophy', ARRAY['cable','straight_bar'], FALSE
    )
ON CONFLICT (name) DO NOTHING;
