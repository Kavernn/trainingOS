-- Migration 026: schema version tracking table
-- Allows run_migrations.py to know which migrations have been applied.

CREATE TABLE IF NOT EXISTS public.schema_migrations (
    version    TEXT        PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.schema_migrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON public.schema_migrations
    FOR ALL TO anon USING (true) WITH CHECK (true);

-- Mark all existing migrations as already applied (idempotent bootstrap).
INSERT INTO public.schema_migrations (version) VALUES
    ('nutrition_entries'),
    ('add_sets_json'),
    ('002_multi_programs'),
    ('003_session_type'),
    ('004_food_catalog'),
    ('005_nutrition_intel'),
    ('006_rpe_numeric'),
    ('007_load_profile'),
    ('008_fix_categories'),
    ('009_fix_categories_2'),
    ('010_session_name'),
    ('011_kv_migration'),
    ('012_workout_sessions_completed'),
    ('013_nutrition_scan'),
    ('014_generated_programs'),
    ('015_programs_cycle_start'),
    ('016_per_set_volume_views'),
    ('017_recovery_hr_moments'),
    ('018_meal_templates'),
    ('019_nutrition_dynamic_goals'),
    ('020_soft_delete_exercises'),
    ('021_day_type_targets'),
    ('022_coach_memory'),
    ('023_active_program_session_override'),
    ('024_exercise_logs_rpe_pain_zone'),
    ('025_pss_unique_date_type'),
    ('026_schema_migrations_tracker')
ON CONFLICT (version) DO NOTHING;
