-- MIGRATION 086 — v_session_category : bascule load_profile → category (2026-07-28)
--
-- Raison : load_profile est renseigné sur <30% des exercices → dénominateurs
-- 1-2 exos par séance, ratios instables (Core & Mobilité classée 'force' à tort
-- car 1/1 = 100%, Push classée 'accessory' car 2/5 = 40%). Le critère `category`
-- est renseigné sur ~100% des exos → dénominateurs fiables (5-8 exos/séance).
--
-- Nouvelle règle prouvée sur 20 dernières séances (2 variantes A/B identiques) :
--   force_exos     = exos où category IN ('push', 'pull', 'legs')
--   classified     = exos où category IS NOT NULL
--   ratio_force    = force_exos / classified
--   session_cat    = 'force' si ratio ≥ 0.5, sinon 'accessory' (unknown si dénom = 0)
--   'core' et 'strength' NE comptent PAS comme force mais entrent dans le
--   dénominateur → Core & Mobilité (legs:1 core:3) = 0.25 → accessory ✓
--
-- CREATE OR REPLACE : garde les mêmes colonnes et types que 085 → pas de
-- dépendance à casser. Safe re-run.

CREATE OR REPLACE VIEW v_session_category WITH (security_invoker = true) AS
WITH session_classification AS (
    SELECT
        el.session_id,
        COUNT(DISTINCT el.exercise_id) FILTER (
            WHERE e.category IN ('push', 'pull', 'legs')
        )                                                   AS force_exos,
        COUNT(DISTINCT el.exercise_id) FILTER (
            WHERE e.category IS NOT NULL
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
