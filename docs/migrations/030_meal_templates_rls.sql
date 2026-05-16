-- 030_meal_templates_rls.sql
-- Fix: meal_templates had RLS enabled but no policy, blocking all access

ALTER TABLE public.meal_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "allow_all_meal_templates"
    ON public.meal_templates FOR ALL USING (true) WITH CHECK (true);
