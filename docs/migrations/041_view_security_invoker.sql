-- Migration 041 : fix v_exercise_current — SECURITY INVOKER
--
-- Supabase signale la vue comme SECURITY DEFINER (exécutée avec les droits
-- du créateur, bypasse le RLS). La recréer avec security_invoker=true force
-- l'exécution avec les droits de l'utilisateur appelant, ce qui respecte le RLS.

DROP VIEW IF EXISTS public.v_exercise_current;

CREATE VIEW public.v_exercise_current
WITH (security_invoker = true)
AS
SELECT
    sub.exercise_id,
    sub.exercise_name,
    sub.type,
    sub.latest_weight,
    sub.latest_reps,
    sub.session_count,
    CASE
        WHEN sub.latest_weight IS NULL OR sub.latest_weight <= 0 THEN NULL
        WHEN sub.max_reps > 20                                   THEN NULL
        WHEN sub.max_reps > 10
            THEN ROUND(sub.latest_weight * (36.0 / (37 - sub.max_reps)), 1)
        ELSE ROUND(sub.latest_weight * (1 + sub.max_reps::NUMERIC / 30), 1)
    END AS estimated_1rm,
    CASE
        WHEN sub.latest_weight IS NULL OR sub.latest_weight <= 0 THEN NULL
        WHEN sub.max_reps > 20 THEN 'none'
        WHEN sub.max_reps > 15 THEN 'low'
        WHEN sub.max_reps > 10 THEN 'medium'
        ELSE                        'high'
    END AS estimated_1rm_confidence
FROM (
    SELECT
        e.id                        AS exercise_id,
        e.name                      AS exercise_name,
        e.type,
        latest.weight               AS latest_weight,
        latest.reps                 AS latest_reps,
        session_counts.session_count,
        COALESCE(
            (SELECT MAX(r::INT)
             FROM unnest(string_to_array(latest.reps, ',')) AS r
             WHERE r ~ '^\d+$'),
            1
        )                           AS max_reps
    FROM exercises e
    LEFT JOIN LATERAL (
        SELECT el.weight, el.reps
        FROM exercise_logs el
        JOIN workout_sessions ws ON ws.id = el.session_id
        WHERE el.exercise_id = e.id
        ORDER BY ws.date DESC
        LIMIT 1
    ) latest ON TRUE
    LEFT JOIN (
        SELECT exercise_id, COUNT(*) AS session_count
        FROM exercise_logs
        GROUP BY exercise_id
    ) session_counts ON session_counts.exercise_id = e.id
) sub;
