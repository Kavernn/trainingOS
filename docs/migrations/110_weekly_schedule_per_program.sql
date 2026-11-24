-- Migration 110 — weekly_schedule lié au programme (planning par programme)
--
-- POURQUOI (incident 2026-11-23) : weekly_schedule était global, clé (day_name, slot).
-- Activer le nouveau programme « Hiver 2027 » (1 séance) a laissé le planning de
-- GymProgramme v4 en place → contexte incohérent (séances planifiées absentes du programme
-- actif) → onglet Aujourd'hui en erreur. Désormais chaque programme a SON planning ;
-- activer un programme active son planning (un programme neuf = tous les jours « Repos »).
--
-- ÉTAT PROD AVANT (vérifié par Vince le 2026-11-23) :
--   weekly_schedule_pkey        PRIMARY KEY (day_name, slot)
--   weekly_schedule_day_slot_key UNIQUE (day_name, slot)   ← doublon, supprimé aussi
--   weekly_schedule_session_id_fkey (conservée)
--   11 lignes, toutes rattachées à GymProgramme v4 (7ddfa7a6-…) sauf Ven/morning
--   (session null = repos) → rattachée à v4 par la reprise ci-dessous.
--
-- Reprise des données : programme de la séance planifiée ; à défaut (repos), GymProgramme v4.
-- Les deux contraintes sur (day_name, slot) sont supprimées (l'unicité restante bloquerait le
-- planning d'un second programme). Nouvelle clé : (program_id, day_name, slot), sans unicité
-- redondante. ON DELETE CASCADE : supprimer un programme supprime son planning.
-- Pas de dollar-quoting, pas de CREATE INDEX (règles migrations TrainingOS) ; la clé
-- primaire est une contrainte. RLS : table existante, policies inchangées.
--
-- DÉPLOIEMENT : le serveur (lectures/écritures par programme) est déployé dans la minute
-- qui suit. Entre les deux, les lectures restent correctes (un seul programme a des
-- lignes) ; l'enregistrement du planning échouerait (on_conflict sur l'ancienne clé).
--
-- EXÉCUTÉE PAR VINCE dans l'éditeur SQL Supabase le 2026-11-23 (soir). Script ci-dessous =
-- texte exact exécuté. Résultat des vérifications :
--   weekly_schedule_pkey PRIMARY KEY (program_id, day_name, slot)
--   weekly_schedule_program_id_fkey (ON DELETE CASCADE) ; weekly_schedule_session_id_fkey
--   plus aucune contrainte sur (day_name, slot) seule
--   lignes : 7ddfa7a6-297b-485f-9208-fccc9b921cce | 11
-- Non inscrite dans schema_migrations.
--
-- Vérification après exécution :
--   SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
--   WHERE conrelid = 'public.weekly_schedule'::regclass ORDER BY conname;
--   → weekly_schedule_pkey PRIMARY KEY (program_id, day_name, slot)
--   → weekly_schedule_program_id_fkey FOREIGN KEY (program_id) REFERENCES programs(id) ON DELETE CASCADE
--   → weekly_schedule_session_id_fkey (inchangée) ; plus de weekly_schedule_day_slot_key
--
--   SELECT count(*) AS lignes,
--          count(*) FILTER (WHERE program_id = '7ddfa7a6-297b-485f-9208-fccc9b921cce') AS v4,
--          count(*) FILTER (WHERE program_id IS NULL) AS sans_programme
--   FROM public.weekly_schedule;
--   → lignes = 11, v4 = 11, sans_programme = 0

ALTER TABLE public.weekly_schedule
    ADD COLUMN IF NOT EXISTS program_id UUID REFERENCES public.programs(id) ON DELETE CASCADE;

UPDATE public.weekly_schedule ws
   SET program_id = ps.program_id
  FROM public.program_sessions ps
 WHERE ws.session_id = ps.id
   AND ws.program_id IS NULL;

UPDATE public.weekly_schedule
   SET program_id = '7ddfa7a6-297b-485f-9208-fccc9b921cce'
 WHERE program_id IS NULL;

ALTER TABLE public.weekly_schedule ALTER COLUMN program_id SET NOT NULL;

ALTER TABLE public.weekly_schedule DROP CONSTRAINT IF EXISTS weekly_schedule_day_slot_key;
ALTER TABLE public.weekly_schedule DROP CONSTRAINT IF EXISTS weekly_schedule_pkey;

ALTER TABLE public.weekly_schedule
    ADD CONSTRAINT weekly_schedule_pkey PRIMARY KEY (program_id, day_name, slot);
