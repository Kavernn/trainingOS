-- 031_fix_set_updated_at_search_path.sql
-- Security fix: pin search_path on set_updated_at to prevent schema-injection attacks

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;
