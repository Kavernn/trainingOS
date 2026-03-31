-- Migration 009: fix remaining category/classification issues
-- 1. Triceps Dip + Skull Crusher: cat pull → push
-- 2. Dumbbell Wrist Curl: load_profile compound_heavy → isolation, scheme 3x12-15

UPDATE public.exercises SET category = 'push'
WHERE name IN ('Triceps Dip', 'Barbell Lying Triceps Extension Skull Crusher');

UPDATE public.exercises SET load_profile = 'isolation', default_scheme = '3x12-15'
WHERE name = 'Dumbbell Wrist Curl';
