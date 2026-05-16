-- 029_neck_cm_weight_deprecation.sql
-- Add neck_cm to body_weight_logs (required for Navy body fat formula)
-- Deprecate user_profile.weight (source of truth is body_weight_logs)

ALTER TABLE body_weight_logs
    ADD COLUMN IF NOT EXISTS neck_cm NUMERIC;

COMMENT ON COLUMN body_weight_logs.neck_cm IS
    'Neck circumference in cm — required for US Navy body fat formula';

COMMENT ON COLUMN user_profile.weight IS
    'DEPRECATED since 2026-05-16. Never written, never read by the app. '
    'Source of truth for body weight is body_weight_logs.weight.';
