-- Migration 005: nutrition intelligence
-- Meal type on entries + macro targets on settings

ALTER TABLE nutrition_entries
    ADD COLUMN IF NOT EXISTS meal_type TEXT
    CHECK (meal_type IN ('matin', 'midi', 'soir', 'collation'));

ALTER TABLE nutrition_settings
    ADD COLUMN IF NOT EXISTS glucides REAL DEFAULT 0;

ALTER TABLE nutrition_settings
    ADD COLUMN IF NOT EXISTS lipides REAL DEFAULT 0;
