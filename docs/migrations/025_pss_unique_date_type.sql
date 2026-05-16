-- Migration 025: add UNIQUE(date, type) constraint to pss_records
-- Prevents multiple PSS questionnaires of the same type on the same day.
-- If duplicates exist, deduplicate first:
--   DELETE FROM pss_records WHERE id NOT IN (
--     SELECT id FROM (
--       SELECT DISTINCT ON (date, type) id FROM pss_records ORDER BY date, type, recorded_at DESC
--     ) sub
--   );

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'unique_pss_per_day_type'
    ) THEN
        ALTER TABLE public.pss_records
            ADD CONSTRAINT unique_pss_per_day_type UNIQUE (date, type);
    END IF;
END $$;
