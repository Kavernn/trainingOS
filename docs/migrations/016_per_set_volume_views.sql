-- MIGRATION 016 — Per-set volume in SQL views (2026-04-27)
-- Replaces the average-weight volume formula with real per-set loads from sets_json.
-- Safe to run multiple times (CREATE OR REPLACE).

CREATE OR REPLACE VIEW v_session_volume WITH (security_invoker = true) AS
SELECT
    ws.id                                               AS session_id,
    ws.date,
    ws.rpe,
    ws.duration_min,
    ROUND(SUM(
        CASE
            WHEN el.sets_json IS NOT NULL AND jsonb_array_length(el.sets_json) > 0
            THEN (
                SELECT COALESCE(SUM(
                    COALESCE(
                        (s->>'set_volume')::NUMERIC,
                        COALESCE((s->>'weight')::NUMERIC, 0) *
                        COALESCE((s->>'reps')::NUMERIC, 0)
                    )
                ), 0)
                FROM jsonb_array_elements(el.sets_json) AS s
            )
            ELSE COALESCE(el.weight, 0) * COALESCE((
                SELECT SUM(r::INT)
                FROM unnest(string_to_array(el.reps, ',')) AS r
                WHERE r ~ '^\d+$'
            ), 0)
        END
    ), 2)                                               AS total_volume,
    COUNT(el.id)                                        AS total_sets,
    SUM(COALESCE((
        SELECT SUM(r::INT)
        FROM unnest(string_to_array(el.reps, ',')) AS r
        WHERE r ~ '^\d+$'
    ), 0))                                              AS total_reps
FROM workout_sessions ws
LEFT JOIN exercise_logs el ON el.session_id = ws.id
GROUP BY ws.id, ws.date, ws.rpe, ws.duration_min;


CREATE OR REPLACE VIEW v_weekly_volume WITH (security_invoker = true) AS
SELECT
    DATE_TRUNC('week', ws.date)                     AS week_start,
    EXTRACT(WEEK FROM ws.date)::INT                 AS week_number,
    EXTRACT(YEAR FROM ws.date)::INT                 AS year,
    ROUND(SUM(
        CASE
            WHEN el.sets_json IS NOT NULL AND jsonb_array_length(el.sets_json) > 0
            THEN (
                SELECT COALESCE(SUM(
                    COALESCE(
                        (s->>'set_volume')::NUMERIC,
                        COALESCE((s->>'weight')::NUMERIC, 0) *
                        COALESCE((s->>'reps')::NUMERIC, 0)
                    )
                ), 0)
                FROM jsonb_array_elements(el.sets_json) AS s
            )
            ELSE COALESCE(el.weight, 0) * COALESCE((
                SELECT SUM(r::INT)
                FROM unnest(string_to_array(el.reps, ',')) AS r
                WHERE r ~ '^\d+$'
            ), 0)
        END
    ), 2)                                           AS total_volume,
    COUNT(DISTINCT ws.id)                           AS session_count,
    COUNT(el.id)                                    AS total_sets
FROM workout_sessions ws
LEFT JOIN exercise_logs el ON el.session_id = ws.id
GROUP BY DATE_TRUNC('week', ws.date), EXTRACT(WEEK FROM ws.date), EXTRACT(YEAR FROM ws.date)
ORDER BY week_start DESC;
