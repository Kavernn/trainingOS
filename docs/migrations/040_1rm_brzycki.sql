-- Migration 040 : correction formule 1RM dans v_exercise_current
--
-- Problème : Epley seul surestime le 1RM au-delà de 10 reps (>12% d'erreur à 15 reps).
-- Un user qui programme ses charges sur une surestimation se blesse.
--
-- Correction :
--   ≤10 reps   → Epley   : weight * (1 + reps / 30)      — précis dans ce range
--   11–20 reps → Brzycki : weight * (36 / (37 - reps))   — conservateur (sous-estime)
--   >20 reps   → NULL    — trop imprécis, ne pas afficher
--
-- Référence : Epley (1985), Brzycki (1993).
--
-- Structure : sous-requête enveloppante pour calculer max_reps une seule fois
-- et l'utiliser dans les deux expressions CASE sans répéter la correlated subquery.

CREATE OR REPLACE VIEW v_exercise_current AS
SELECT
    sub.exercise_id,
    sub.exercise_name,
    sub.type,
    sub.latest_weight,
    sub.latest_reps,
    sub.session_count,
    -- 1RM estimé : Epley ≤10 reps, Brzycki 11-20 reps, NULL >20 reps
    CASE
        WHEN sub.latest_weight IS NULL OR sub.latest_weight <= 0 THEN NULL
        WHEN sub.max_reps > 20                                   THEN NULL
        WHEN sub.max_reps > 10
            THEN ROUND(sub.latest_weight * (36.0 / (37 - sub.max_reps)), 1)
        ELSE ROUND(sub.latest_weight * (1 + sub.max_reps::NUMERIC / 30), 1)
    END                                                          AS estimated_1rm,
    -- Niveau de confiance de l'estimation
    CASE
        WHEN sub.latest_weight IS NULL OR sub.latest_weight <= 0 THEN NULL
        WHEN sub.max_reps > 20 THEN 'none'
        WHEN sub.max_reps > 15 THEN 'low'
        WHEN sub.max_reps > 10 THEN 'medium'
        ELSE                        'high'
    END                                                          AS estimated_1rm_confidence
FROM (
    SELECT
        e.id                        AS exercise_id,
        e.name                      AS exercise_name,
        e.type,
        latest.weight               AS latest_weight,
        latest.reps                 AS latest_reps,
        session_counts.session_count,
        -- max_reps calculé ici une seule fois, réutilisé dans les deux CASE ci-dessus
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
