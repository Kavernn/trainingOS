-- Day Composer occurrences. Apply before the occurrence-aware API and client.
-- Historical key is declared by 087a, with the two-column key removed by 087b.
-- Fail closed if that expected schema is absent; transaction retains the old key.
BEGIN;
ALTER TABLE public.exercise_logs
    ADD COLUMN occurrence_key text NOT NULL DEFAULT '';
ALTER TABLE public.exercise_logs
    ADD CONSTRAINT exercise_logs_occurrence_key_length CHECK (octet_length(occurrence_key) <= 160);
ALTER TABLE public.exercise_logs
    DROP CONSTRAINT exercise_logs_session_id_exercise_id_side_key;
ALTER TABLE public.exercise_logs
    ADD CONSTRAINT exercise_logs_occurrence_identity_key
    UNIQUE (session_id, exercise_id, side, occurrence_key);
COMMIT;
