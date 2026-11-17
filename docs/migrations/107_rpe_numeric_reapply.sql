-- Migration 107 — Réapplication de 006 : rpe en NUMERIC(4,1) (workout_sessions, hiit_logs)
--
-- POURQUOI : 006_rpe_numeric.sql (SMALLINT → NUMERIC(4,1)) n'avait jamais été
-- exécutée en prod. 026_schema_migrations_tracker.sql l'a inscrite comme appliquée
-- par un bootstrap en bloc (« Mark all existing migrations as already applied »),
-- sans vérification. La prod est restée en smallint alors que docs/schema.sql et le
-- code documentaient NUMERIC(4,1).
--
-- INCIDENT 2026-11-17 : fin de séance du soir « Mardi PM — Pull A — suite » refusée
-- (HTTP 500 « Impossible de marquer la séance du soir comme terminée »). Le RPE 7.5
-- envoyé tel quel par update_workout_session_by_type a levé 22P02 « invalid input
-- syntax for type smallint ». Le chemin du matin arrondissait à l'entier et masquait
-- la dérive.
--
-- POURQUOI LES VUES : ALTER COLUMN TYPE est refusé sur une colonne utilisée par une
-- vue. Les 3 vues dépendantes sont supprimées puis recréées depuis leurs définitions
-- PROD (pg_get_viewdef), pas depuis les fichiers du dépôt. Les GRANT sont rétablis.
-- La contrainte workout_sessions_rpe_check est conservée par ALTER TYPE.
-- v_exercise_current n'utilise pas rpe : non touchée.
--
-- EXÉCUTÉE PAR VINCE dans l'éditeur SQL Supabase le 2026-11-17. Script ci-dessous =
-- texte exact exécuté. Vérifications : type numeric(4,1) sur les 2 tables ; nombres de
-- lignes des vues 284 / 38 / 284 identiques avant/après ; sommes volume / reps /
-- volume semaine identiques (3236690.93 / 36526 / 3236690.94) ; regex '^\d+$' préservée.
-- Non inscrite dans schema_migrations (le script exécuté ne l'insère pas).

BEGIN;

DROP VIEW public.v_session_category;
DROP VIEW public.v_weekly_volume;
DROP VIEW public.v_session_volume;

ALTER TABLE public.workout_sessions ALTER COLUMN rpe TYPE numeric(4,1);
ALTER TABLE public.hiit_logs        ALTER COLUMN rpe TYPE numeric(4,1);

CREATE VIEW public.v_session_volume WITH (security_invoker = true) AS
 SELECT ws.id AS session_id,
    ws.date,
    ws.rpe,
    ws.duration_min,
    round(sum(
        CASE
            WHEN el.sets_json IS NOT NULL AND jsonb_array_length(el.sets_json) > 0 THEN ( SELECT COALESCE(sum(COALESCE((s.value ->> 'set_volume'::text)::numeric, COALESCE((s.value ->> 'weight'::text)::numeric, 0::numeric) * COALESCE((s.value ->> 'reps'::text)::numeric, 0::numeric))), 0::numeric) AS "coalesce"
               FROM jsonb_array_elements(el.sets_json) s(value))
            ELSE COALESCE(el.weight, 0::numeric) * COALESCE(( SELECT sum(r.r::integer) AS sum
               FROM unnest(string_to_array(el.reps, ','::text)) r(r)
              WHERE r.r ~ '^\d+$'::text), 0::bigint)::numeric
        END), 2) AS total_volume,
    count(el.id) AS total_sets,
    sum(COALESCE(( SELECT sum(r.r::integer) AS sum
           FROM unnest(string_to_array(el.reps, ','::text)) r(r)
          WHERE r.r ~ '^\d+$'::text), 0::bigint)) AS total_reps
   FROM public.workout_sessions ws
     LEFT JOIN public.exercise_logs el ON el.session_id = ws.id
  GROUP BY ws.id, ws.date, ws.rpe, ws.duration_min;

CREATE VIEW public.v_weekly_volume WITH (security_invoker = true) AS
 SELECT date_trunc('week'::text, ws.date::timestamp with time zone) AS week_start,
    EXTRACT(week FROM ws.date)::integer AS week_number,
    EXTRACT(year FROM ws.date)::integer AS year,
    round(sum(
        CASE
            WHEN el.sets_json IS NOT NULL AND jsonb_array_length(el.sets_json) > 0 THEN ( SELECT COALESCE(sum(COALESCE((s.value ->> 'set_volume'::text)::numeric, COALESCE((s.value ->> 'weight'::text)::numeric, 0::numeric) * COALESCE((s.value ->> 'reps'::text)::numeric, 0::numeric))), 0::numeric) AS "coalesce"
               FROM jsonb_array_elements(el.sets_json) s(value))
            ELSE COALESCE(el.weight, 0::numeric) * COALESCE(( SELECT sum(r.r::integer) AS sum
               FROM unnest(string_to_array(el.reps, ','::text)) r(r)
              WHERE r.r ~ '^\d+$'::text), 0::bigint)::numeric
        END), 2) AS total_volume,
    count(DISTINCT ws.id) AS session_count,
    count(el.id) AS total_sets
   FROM public.workout_sessions ws
     LEFT JOIN public.exercise_logs el ON el.session_id = ws.id
  GROUP BY (date_trunc('week'::text, ws.date::timestamp with time zone)), (EXTRACT(week FROM ws.date)), (EXTRACT(year FROM ws.date))
  ORDER BY (date_trunc('week'::text, ws.date::timestamp with time zone)) DESC;

CREATE VIEW public.v_session_category WITH (security_invoker = true) AS
 WITH session_classification AS (
         SELECT el.session_id,
            count(DISTINCT el.exercise_id) FILTER (WHERE e.category = ANY (ARRAY['push'::text, 'pull'::text, 'legs'::text])) AS force_exos,
            count(DISTINCT el.exercise_id) FILTER (WHERE e.category IS NOT NULL) AS classified_exos
           FROM public.exercise_logs el
             JOIN public.exercises e ON e.id = el.exercise_id
          GROUP BY el.session_id
        )
 SELECT sv.session_id,
    sv.date,
    sv.rpe,
    sv.duration_min,
    sv.total_volume,
    sv.total_sets,
    sv.total_reps,
    COALESCE(sc.force_exos, 0::bigint) AS force_exos,
    COALESCE(sc.classified_exos, 0::bigint) AS classified_exos,
        CASE
            WHEN COALESCE(sc.classified_exos, 0::bigint) = 0 THEN NULL::numeric
            ELSE round(sc.force_exos::numeric / sc.classified_exos::numeric, 3)
        END AS ratio_force,
        CASE
            WHEN COALESCE(sc.classified_exos, 0::bigint) = 0 THEN 'unknown'::text
            WHEN (sc.force_exos::numeric / sc.classified_exos::numeric) >= 0.5 THEN 'force'::text
            ELSE 'accessory'::text
        END AS session_category
   FROM public.v_session_volume sv
     LEFT JOIN session_classification sc ON sc.session_id = sv.session_id;

GRANT ALL ON public.v_session_volume, public.v_weekly_volume, public.v_session_category
  TO anon, authenticated, service_role;

COMMIT;
