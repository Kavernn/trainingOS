-- Migration 040 : correction formule 1RM dans v_exercise_current
--
-- Problème : Epley seul surestime le 1RM au-delà de 10 reps (>12% d'erreur à 15 reps).
-- Un user qui programme ses charges sur une surestimation se blesse.
--
-- Correction :
--   ≤10 reps  → Epley   : weight * (1 + reps / 30)       — précis dans ce range
--   11–20 reps → Brzycki : weight * (36 / (37 - reps))   — conservateur (sous-estime)
--   >20 reps   → NULL    — trop imprécis, ne pas afficher
--
-- Référence : Epley (1985), Brzycki (1993).

CREATE OR REPLACE VIEW v_exercise_current AS
SELECT
    e.id                                            AS exercise_id,
    e.name                                          AS exercise_name,
    e.type,
    latest.weight                                   AS latest_weight,
    latest.reps                                     AS latest_reps,
    session_counts.session_count,
    -- 1RM estimé : Epley ≤10 reps, Brzycki 11-20 reps, NULL >20 reps
    CASE
        WHEN latest.weight IS NULL OR latest.weight <= 0 THEN NULL
        WHEN max_reps.val > 20 THEN NULL
        WHEN max_reps.val > 10 THEN ROUND(latest.weight * (36.0 / (37 - max_reps.val)), 1)
        ELSE ROUND(latest.weight * (1 + max_reps.val::NUMERIC / 30), 1)
    END                                             AS estimated_1rm,
    -- Niveau de confiance de l'estimation
    CASE
        WHEN max_reps.val IS NULL OR latest.weight IS NULL OR latest.weight <= 0 THEN NULL
        WHEN max_reps.val > 20 THEN 'none'
        WHEN max_reps.val > 15 THEN 'low'
        WHEN max_reps.val > 10 THEN 'medium'
        ELSE 'high'
    END                                             AS estimated_1rm_confidence
FROM exercises e
LEFT JOIN LATERAL (
    SELECT el.weight, el.reps
    FROM exercise_logs el
    JOIN workout_sessions ws ON ws.id = el.session_id
    WHERE el.exercise_id = e.id
    ORDER BY ws.date DESC
    LIMIT 1
) latest ON TRUE
LEFT JOIN LATERAL (
    SELECT GREATEST(
        COALESCE(
            (SELECT MAX(r::INT)
             FROM unnest(string_to_array(latest.reps, ',')) AS r
             WHERE r ~ '^\d+$'),
            1
        )
    ) AS val
) max_reps ON TRUE
LEFT JOIN (
    SELECT exercise_id, COUNT(*) AS session_count
    FROM exercise_logs
    GROUP BY exercise_id
) session_counts ON session_counts.exercise_id = e.id;
