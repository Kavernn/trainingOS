-- MIGRATION 085 — Vue v_session_category (2026-07-28)
-- Classifie chaque séance en 'force' | 'accessory' | 'unknown' selon la nature
-- des exercices loggés (ratio d'exos compound vs isolation/endurance).
--
-- Règle : force-like = load_profile IN ('compound_heavy','compound_hypertrophy').
-- Seuil : ratio ≥ 0.5 → 'force', sinon → 'accessory'. Aucun exo classifié
-- (load_profile NULL sur tout) → 'unknown' (exclue des séries temporelles).
--
-- Ne classifie PAS par nom de séance (fragile au renaming). Ne stocke pas de
-- flag sur program_sessions (Stratégie A nécessiterait migration + backfill).
--
-- Safe re-run : CREATE OR REPLACE. security_invoker = true → hérite RLS des
-- tables source (même pattern que v_session_volume).

CREATE OR REPLACE VIEW v_session_category WITH (security_invoker = true) AS
WITH session_classification AS (
    SELECT
        el.session_id,
        COUNT(DISTINCT el.exercise_id) FILTER (
            WHERE e.load_profile IN ('compound_heavy', 'compound_hypertrophy')
        )                                                   AS force_exos,
        COUNT(DISTINCT el.exercise_id) FILTER (
            WHERE e.load_profile IS NOT NULL
        )                                                   AS classified_exos
    FROM exercise_logs el
    JOIN exercises e ON e.id = el.exercise_id
    GROUP BY el.session_id
)
SELECT
    sv.session_id,
    sv.date,
    sv.rpe,
    sv.duration_min,
    sv.total_volume,
    sv.total_sets,
    sv.total_reps,
    COALESCE(sc.force_exos, 0)                              AS force_exos,
    COALESCE(sc.classified_exos, 0)                         AS classified_exos,
    CASE
        WHEN COALESCE(sc.classified_exos, 0) = 0            THEN NULL
        ELSE ROUND(sc.force_exos::NUMERIC / sc.classified_exos, 3)
    END                                                     AS ratio_force,
    CASE
        WHEN COALESCE(sc.classified_exos, 0) = 0            THEN 'unknown'
        WHEN sc.force_exos::NUMERIC / sc.classified_exos >= 0.5 THEN 'force'
        ELSE 'accessory'
    END                                                     AS session_category
FROM v_session_volume sv
LEFT JOIN session_classification sc ON sc.session_id = sv.session_id;
