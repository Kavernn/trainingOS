-- 019_nutrition_dynamic_goals.sql
-- Per-day-type calorie targets (training vs rest day differentiation)

ALTER TABLE nutrition_settings
    ADD COLUMN IF NOT EXISTS training_calories INTEGER,
    ADD COLUMN IF NOT EXISTS rest_calories     INTEGER;
