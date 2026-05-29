-- Migration 056: glucides_target, lipides_target, nutrition_end_time
ALTER TABLE nutrition_settings
  ADD COLUMN IF NOT EXISTS glucides_target    INTEGER DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS lipides_target     INTEGER DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS nutrition_end_time TIME    DEFAULT '21:00:00';
