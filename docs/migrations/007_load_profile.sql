-- Migration 007: add load_profile column to exercises
-- load_profile classifies exercises by rep-range intent:
--   compound_heavy       → 5–7, 6–8  (barbell multi-joint, neurological demand)
--   compound_hypertrophy → 8–12      (multi-joint, moderate reps)
--   isolation            → 12–15+    (single-joint)
--   NULL                 → core / mobility / uncategorized

ALTER TABLE public.exercises
    ADD COLUMN IF NOT EXISTS load_profile TEXT
    CHECK (load_profile IN ('compound_heavy', 'compound_hypertrophy', 'isolation'));

-- ── Seed: Composé lourd ──────────────────────────────────────────────────────
UPDATE public.exercises SET load_profile = 'compound_heavy' WHERE name IN (
    'Back Squat',
    'Barbell Close-Grip Bench Press',
    'Barbell Decline Bench Press',
    'Barbell Front Squat',
    'Barbell Incline Bench Press',
    'Barbell Sumo Deadlift',
    'Bench Press',
    'Chin-Up',
    'Deadlift',
    'Overhead Press',
    'Pause Bench Press',
    'Pull-Up',
    'Rack Pull',
    'Weighted Squat'
);

-- ── Seed: Composé hypertrophie ───────────────────────────────────────────────
UPDATE public.exercises SET load_profile = 'compound_hypertrophy' WHERE name IN (
    'Barbell Bent Over Row',
    'Barbell Glute Bridge',
    'Barbell Good Morning',
    'Barbell Hack Squat',
    'Barbell Lunge',
    'Barbell Romanian Deadlift',
    'Barbell Row',
    'Burpee',
    'Cable Pull Over',
    'Cable Seated Row',
    'DB Bench Press',
    'Dumbbell Arnold Press',
    'Dumbbell Decline Bench Press',
    'Farmers Walk',
    'Incline Dumbbell Press',
    'Inverted Row',
    'Jump Squat',
    'Lat Pulldown',
    'Leg Press',
    'Lever T Bar Row',
    'Romanian Deadlift',
    'Seated Row',
    'Shoulder Overhead Press',
    'Smith Leg Press',
    'T-Bar Row',
    'Triceps Dip',
    'Walking Lunge'
);

-- ── Seed: Isolation ──────────────────────────────────────────────────────────
UPDATE public.exercises SET load_profile = 'isolation' WHERE name IN (
    'Barbell Curl',
    'Barbell Preacher Curl',
    'Barbell Shrug',
    'Barbell Upright Row',
    'Cable Curl',
    'Cable Lateral Raise',
    'Calf Raise',
    'Dumbbell Biceps Curl',
    'Dumbbell Concentration Curl',
    'Dumbbell Fly',
    'Dumbbell Front Raise',
    'Dumbbell Hammer Curl',
    'Dumbbell Lateral Raise',
    'Dumbbell Shrug',
    'Dumbbell Wrist Curl',
    'Face Pull',
    'Hammer Curl',
    'Lateral Raises',
    'Lateral Raises (un bras)',
    'Leg Curl',
    'Lever Leg Extension',
    'Lever Seated Fly',
    'Lever Seated Leg Curl',
    'Reverse curls',
    'Smith Standing Leg Calf Raise',
    'Triceps Extension',
    'Triceps Pushdown'
);

-- Abs, Hanging Leg Raise, Plank, Push-Up, Russian Twist, Weighted Crunch → NULL (default)
