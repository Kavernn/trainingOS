-- Migration 111 — chaque exercice de programme possède ses propres valeurs
--
-- POURQUOI (build 3, validé par Vince le 2026-11-24) : un exercice de programme ne gardait
-- que son `scheme`. Le repos venait de la bibliothèque (exercises.rest_seconds, commun à tous
-- les programmes), le RIR cible et la notion de bonus n'existaient pas, et modifier un
-- exercice dans la bibliothèque réécrivait le scheme dans TOUS les programmes
-- (db_exercises.py:89). Règle : la bibliothèque fournit des valeurs PAR DÉFAUT, utilisées
-- seulement à l'ajout d'un exercice dans une séance ; l'exercice de programme possède les
-- siennes (scheme, target_rir_min/max, rest_seconds, is_optional).
--
-- COLONNES (program_block_exercises) :
--   rest_seconds    INTEGER  NULL = « selon besoin » → l'app utilise le repos de la bibliothèque
--   target_rir_min  SMALLINT } RIR cible, 0 à 5 ; une seule valeur → min = max ;
--   target_rir_max  SMALLINT } NULL/NULL = pas de cible (« Au choix »)
--   is_optional     BOOLEAN  bonus : affiché « Bonus », hors progression de séance et passage
--                            automatique, jamais compté comme sauté
--
-- REPRISE : tous les exercices de programme existants (GymProgramme v4, Hiver 2027) reçoivent
-- le repos actuel de leur exercice dans la bibliothèque — aucun changement de comportement.
-- Vérifié avant (lecture API 2026-11-24, AVANT l'import d'Hiver 2027) : aucun
-- exercises.rest_seconds NULL sur 140 exercices. ERREUR : les 5 exercices créés ensuite par
-- l'import l'ont été SANS rest_seconds → 4 lignes de programme restent à repos vide (cf. résultats).
-- RIR vide et is_optional = false partout. Les valeurs du classeur d'Hiver 2027 (RIR, repos,
-- 12 bonus) sont réappliquées APRÈS le déploiement serveur, par la route de l'app (jamais en SQL).
--
-- HORS PÉRIMÈTRE : la fonction apply_progression (096) n'est PAS modifiée ici (règle : pas de
-- fonction / dollar-quoting dans les migrations). Traitée avec le Serveur B.
--
-- Pas de dollar-quoting, pas d'index (règles migrations TrainingOS).
-- RLS : table existante, policies inchangées.
--
-- Vérification après exécution :
--   SELECT column_name, data_type, is_nullable, column_default FROM information_schema.columns
--   WHERE table_name = 'program_block_exercises'
--     AND column_name IN ('rest_seconds','target_rir_min','target_rir_max','is_optional')
--   ORDER BY column_name;
--   → is_optional boolean NO false ; rest_seconds integer YES ; target_rir_max/min smallint YES
--
--   SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
--   WHERE conrelid = 'public.program_block_exercises'::regclass
--     AND conname IN ('pbe_rest_seconds_positive','pbe_target_rir_range');
--   → 2 lignes
--
--   SELECT p.name, count(*) AS exercices,
--          count(*) FILTER (WHERE pe.rest_seconds IS NULL) AS repos_vide,
--          count(*) FILTER (WHERE pe.rest_seconds IS DISTINCT FROM ex.rest_seconds) AS repos_different,
--          count(*) FILTER (WHERE pe.is_optional) AS bonus
--   FROM public.program_block_exercises pe
--   JOIN public.exercises ex ON ex.id = pe.exercise_id
--   JOIN public.program_blocks b ON b.id = pe.block_id
--   JOIN public.program_sessions s ON s.id = b.session_id
--   JOIN public.programs p ON p.id = s.program_id
--   GROUP BY p.name ORDER BY p.name;
--   → attendu corrigé : GymProgramme v4 65 lignes (une ligne par exercice ET par séance ;
--     52 = exercices distincts, pas des lignes), Hiver 2027 53 lignes (Plate Pinch Hold retiré
--     par Vince après l'import) ; bonus = 0.
--
-- EXÉCUTÉE PAR VINCE dans l'éditeur SQL Supabase le 2026-11-24. Script ci-dessous = texte exact
-- exécuté. Résultats :
--   colonnes : is_optional boolean NOT NULL DEFAULT false ; rest_seconds integer, target_rir_min,
--     target_rir_max smallint nullables — conformes
--   total 118 lignes, bonus 0 ; GymProgramme v4 65 lignes, repos_vide 0, repos_different 0 ;
--   Hiver 2027 53 lignes, repos_vide 4 = Single-Arm Cable Triceps Pushdown, Single-Leg DB Calf
--     Raise, Single-Arm Cable Row, Straight-Arm Cable Pulldown (exercices créés sans repos en
--     bibliothèque → rien à copier). Correction : repos par défaut en bibliothèque, sur accord
--     de Vince, puis garde « repos obligatoire » à la création d'exercice (Serveur A).
-- Non inscrite dans schema_migrations.

ALTER TABLE public.program_block_exercises ADD COLUMN IF NOT EXISTS rest_seconds INTEGER;
ALTER TABLE public.program_block_exercises ADD COLUMN IF NOT EXISTS target_rir_min SMALLINT;
ALTER TABLE public.program_block_exercises ADD COLUMN IF NOT EXISTS target_rir_max SMALLINT;
ALTER TABLE public.program_block_exercises ADD COLUMN IF NOT EXISTS is_optional BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.program_block_exercises DROP CONSTRAINT IF EXISTS pbe_rest_seconds_positive;
ALTER TABLE public.program_block_exercises
    ADD CONSTRAINT pbe_rest_seconds_positive CHECK (rest_seconds IS NULL OR rest_seconds > 0);

ALTER TABLE public.program_block_exercises DROP CONSTRAINT IF EXISTS pbe_target_rir_range;
ALTER TABLE public.program_block_exercises
    ADD CONSTRAINT pbe_target_rir_range CHECK (
        (target_rir_min IS NULL AND target_rir_max IS NULL)
        OR (target_rir_min BETWEEN 0 AND 5 AND target_rir_max BETWEEN 0 AND 5
            AND target_rir_min <= target_rir_max)
    );

UPDATE public.program_block_exercises pe
   SET rest_seconds = ex.rest_seconds
  FROM public.exercises ex
 WHERE pe.exercise_id = ex.id
   AND pe.rest_seconds IS NULL;
