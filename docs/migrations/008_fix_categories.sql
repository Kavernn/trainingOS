-- Migration 008: fix exercises.category — replace invalid 'strength' value
-- and fill missing categories. Required for upper/lower body detection.

-- ── Fix category='strength' → correct values ─────────────────────────────
UPDATE public.exercises SET category = 'legs'  WHERE name IN ('Back Squat','Calf Raise','Deadlift','Leg Curl','Leg Press','Romanian Deadlift');
UPDATE public.exercises SET category = 'push'  WHERE name IN ('Bench Press','DB Bench Press','Lateral Raises (un bras)','Triceps Extension');
UPDATE public.exercises SET category = 'pull'  WHERE name IN ('Barbell Row','Face Pull','Hammer Curl','Lat Pulldown','Seated Row','T-Bar Row');
UPDATE public.exercises SET category = 'core'  WHERE name = 'Abs';

-- ── Fill category='' or NULL ──────────────────────────────────────────────
UPDATE public.exercises SET category = 'pull'  WHERE name IN ('Cable Seated Row','Chin-Up','Triceps Dip') AND (category IS NULL OR category = '');
UPDATE public.exercises SET category = 'push'  WHERE name IN ('Lateral Raises','Overhead Press','Pause Bench Press') AND (category IS NULL OR category = '');
UPDATE public.exercises SET category = 'legs'  WHERE name = 'Weighted Squat' AND (category IS NULL OR category = '');

-- ── Fix missing load_profile ──────────────────────────────────────────────
UPDATE public.exercises SET load_profile = 'isolation' WHERE name = 'Barbell Lying Triceps Extension Skull Crusher';
-- Abs, Push-Up → intentionally NULL (core / unclassified bodyweight)
