-- 090_v4_new_exercises.sql
-- 15 exercices NOUVEAU pour GymProgramme v4.
-- Tokens (muscle_group/specific FR, movement_pattern Title-Case) copiés du
-- vocabulaire LIVE de la table exercises via ancres validées — pas du schema.sql
-- (doc en retard sur la donnée).
-- Idempotent : ON CONFLICT(name) DO NOTHING protège tout homonyme existant
-- (Barbell Shrug et Rear Delt Fly, déjà présents, sont volontairement HORS
-- de cette liste — réutilisés tels quels en diff 4).

INSERT INTO exercises
  (name, muscle_group, muscle_specific, weight_type, movement_pattern, tracking_type, default_scheme)
VALUES
  ('Band Shoulder CARs',           'Épaules',           'Deltoïde postérieur', 'endurance',    'Rotation',        'time', '2x5'),
  ('Medicine Ball Chest Pass',     'Pectoraux',         'Pectoral moyen',      'endurance',    'Plyometric',      'reps', '4x5'),
  ('Incline Cable Fly',            'Pectoraux',         'Pectoral supérieur',  'cable_double', 'Horizontal Push', 'reps', '3x12-15'),
  ('Cable Crossover',              'Pectoraux',         'Pectoral inférieur',  'cable_double', 'Horizontal Push', 'reps', '3x12-15'),
  ('Cat-Cow + Thoracic Rotation',  'Mobility',          'Thoracique',          'bodyweight',   'Rotation',        'time', '2x8'),
  ('Barbell Jump Shrug',           'Trapèzes',          'Trapèze supérieur',   'barbell',      'Plyometric',      'reps', '4x3'),
  ('Broad Jump',                   'Jambes',            'Quadriceps',          'bodyweight',   'Plyometric',      'reps', '3x3'),
  ('Wall Slides',                  'Épaules',           'Trapèze inférieur',   'bodyweight',   'Gainage',         'reps', '2x10'),
  ('Medicine Ball Overhead Throw', 'Épaules',           'Deltoïde antérieur',  'endurance',    'Plyometric',      'reps', '4x5'),
  ('Seated Z Press',               'Épaules',           'Deltoïde antérieur',  'barbell',      'Vertical Push',   'reps', '3x6-10'),
  ('Band Pull-Apart',              'Épaules',           'Deltoïde postérieur', 'bodyweight',   'Horizontal Pull', 'reps', '2x15'),
  ('Medicine Ball Slam',           'Dos',               'Grand dorsal',        'endurance',    'Plyometric',      'reps', '4x5'),
  ('Reverse Curl',                 'Biceps+Avant-bras', 'Brachioradialis',     'barbell',      'Elbow Flexion',   'reps', '3x10-15'),
  ('Lateral Bound',                'glutes',            'Moyen fessier',       'bodyweight',   'Plyometric',      'reps', '3x4'),
  ('Hollow Body Crunch',           'Core',              'Droit abdominal',     'bodyweight',   'Gainage',         'time', '3x30s')
ON CONFLICT (name) DO NOTHING;
