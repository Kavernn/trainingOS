-- Migration 112 — apply_progression lit et écrit le scheme DE LA SÉANCE, jamais la bibliothèque
--
-- POURQUOI (build 3, Serveur B, validé par Vince le 2026-11-24) : la version 096 comparait le
-- scheme proposé à exercises.default_scheme (bibliothèque) et écrivait default_scheme ET le
-- scheme de la séance. Règle : la bibliothèque ne fournit qu'un défaut (copié à l'ajout) ;
-- l'exercice de programme possède son scheme. Un même exercice peut avoir deux schemes
-- (ex. Back Squat mer 3x5-8 / sam 3x6-8 dans Hiver 2027).
--
-- CHANGEMENTS (tout le reste identique à 096) :
--   * scheme courant = program_block_exercises.scheme de (programme, séance), verrouillé FOR UPDATE ;
--   * contrôle de concurrence : current_weight ET ce scheme de séance (au lieu de default_scheme) ;
--   * exercises : current_weight, progression_reference, progression_schemes — JAMAIS default_scheme ;
--   * program_block_exercises.scheme écrit pour cette seule séance de ce seul programme ;
--   * refus 400 si le nouveau scheme est NULL alors que la séance porte l'exercice.
-- Signature inchangée : apply_progression(p JSONB) RETURNS JSONB, SECURITY INVOKER,
-- EXECUTE réservé à service_role. Atomicité : une fonction plpgsql = une transaction.
--
-- EXCEPTION À LA RÈGLE « pas de dollar-quoting » validée par Vince pour ce cas (même méthode
-- que 096 et 101, toutes deux en production).
--
-- DÉPLOIEMENT : le serveur (expected_current_scheme = scheme de séance) n'est déployé
-- qu'APRÈS le contrôle ci-dessous. Entre les deux : une progression dont le scheme de séance
-- diffère du défaut de bibliothèque est refusée en 409 explicite (aucune écriture erronée).
--
-- VÉRIFICATION APRÈS APPLICATION (à coller à Claude) :
--   SELECT pg_get_functiondef('public.apply_progression(jsonb)'::regprocedure);
--   SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args,
--          pg_get_function_result(p.oid) AS result, p.prosecdef AS security_definer,
--          has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
--          has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_exec
--   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public' AND p.proname = 'apply_progression';
--   → 1 seule ligne : args « p jsonb », result « jsonb », security_definer false,
--     anon_exec false, service_exec true
--   Dans pg_get_functiondef, contrôler :
--     1. signature : public.apply_progression(p jsonb) RETURNS jsonb, SECURITY INVOKER,
--        SET search_path TO 'public' ;
--     2. lecture du scheme de séance : « SELECT pe.scheme INTO cur_scheme » avec les jointures
--        program_blocks / program_sessions et « s.program_id = pid AND s.name = p->>'session_name' » ;
--     3. CAS : « cur_scheme IS DISTINCT FROM p->>'expected_current_scheme' » ;
--        AUCUNE occurrence de « ex.default_scheme IS DISTINCT FROM » ;
--     4. l'UPDATE public.exercises ne contient PAS « default_scheme = » (seulement
--        current_weight, progression_reference, progression_schemes) ;
--     5. UPDATE public.program_block_exercises … SET scheme = new_scheme filtré par pid + séance.

-- EXÉCUTÉE PAR VINCE dans l'éditeur SQL Supabase le 2026-11-24. Script ci-dessous = texte exact
-- exécuté. Résultats :
--   privilèges : p jsonb | jsonb | security_definer false | anon_exec false | service_exec true
--   contrôle automatique : tout à true (invoker, scheme de séance lu, jointure séance, plus de
--     contrôle sur la bibliothèque, default_scheme jamais écrit, écriture program_block_exercises)
--   pg_get_functiondef relu par Vince : les 5 points conformes.
-- Non inscrite dans schema_migrations.
--
-- DETTE (relevée par Vince) : la regex du nouveau scheme accepte le suffixe « s » mais pas « m »
-- → une progression de scheme sur un exercice à distance (Farmer's Carry 2x30-40m) renverrait 400.
-- À traiter seulement si une progression sur la distance est ajoutée ; fonction non modifiée.

BEGIN;
CREATE OR REPLACE FUNCTION public.apply_progression(p JSONB) RETURNS JSONB
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $fn$
DECLARE
    ex public.exercises%ROWTYPE;
    w NUMERIC;
    cur_scheme TEXT;
    has_row BOOLEAN;
    new_scheme TEXT;
    pid UUID := (p->>'program_id')::UUID;
    active_pid UUID;
BEGIN
    -- Hold the active context while writing the reference and programme prescription.
    SELECT active_program_id INTO active_pid FROM public.user_profile WHERE id = 1 FOR SHARE;
    IF active_pid IS NOT NULL AND active_pid IS DISTINCT FROM pid THEN
        RETURN jsonb_build_object('success',false,'status',409,'error','Programme modifié');
    END IF;
    SELECT * INTO ex FROM public.exercises WHERE name = p->>'exercise_name'
        AND deleted_at IS NULL FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success',false,'status',404,'error','Exercice introuvable');
    END IF;
    -- Scheme de la séance (source de vérité), verrouillé : jamais celui de la bibliothèque.
    SELECT pe.scheme INTO cur_scheme FROM public.program_block_exercises pe
        JOIN public.program_blocks b ON b.id = pe.block_id
        JOIN public.program_sessions s ON s.id = b.session_id
        WHERE pe.exercise_id = ex.id AND s.program_id = pid AND s.name = p->>'session_name'
        LIMIT 1
        FOR UPDATE OF pe;
    has_row := FOUND;
    IF ex.current_weight IS DISTINCT FROM (p->>'expected_current_weight')::NUMERIC
        OR cur_scheme IS DISTINCT FROM p->>'expected_current_scheme' THEN
        RETURN jsonb_build_object('success',false,'status',409,'error','Recommandation devenue obsolète');
    END IF;
    w := CASE WHEN p->>'restore'='true' THEN (p->>'suggested_weight')::NUMERIC ELSE COALESCE((p->>'suggested_weight')::NUMERIC, ex.current_weight) END;
    new_scheme := CASE WHEN p->>'restore'='true' THEN p->>'suggested_scheme' ELSE COALESCE(p->>'suggested_scheme', cur_scheme) END;
    IF w < 0 OR w = 'NaN'::NUMERIC OR (new_scheme IS NOT NULL AND new_scheme !~ '^[1-9][0-9]*x[1-9][0-9]*(-[1-9][0-9]*)?s?$')
        OR (has_row AND new_scheme IS NULL) THEN
        RETURN jsonb_build_object('success',false,'status',400,'error','Valeurs invalides');
    END IF;
    IF w IS NOT DISTINCT FROM ex.current_weight AND new_scheme IS NOT DISTINCT FROM cur_scheme THEN
        RETURN jsonb_build_object('success',false,'status',400,'error','Aucun changement');
    END IF;
    IF new_scheme IS DISTINCT FROM cur_scheme AND NOT has_row THEN
        RETURN jsonb_build_object('success',false,'status',409,'error','Prescription introuvable dans cette séance');
    END IF;
    -- Bibliothèque : charge et référence de coaching seulement. default_scheme n'est JAMAIS écrit.
    UPDATE public.exercises SET current_weight=w,
        progression_reference=TRUE,
        progression_schemes=CASE WHEN new_scheme IS DISTINCT FROM cur_scheme
            THEN ex.progression_schemes || jsonb_build_object(pid::text || '/' || (p->>'session_name'),new_scheme)
            ELSE ex.progression_schemes END
        WHERE id=ex.id;
    IF new_scheme IS DISTINCT FROM cur_scheme THEN
        UPDATE public.program_block_exercises AS pe SET scheme=new_scheme
        FROM public.program_blocks AS b, public.program_sessions AS s
        WHERE pe.exercise_id=ex.id AND pe.block_id=b.id AND b.session_id=s.id
            AND s.program_id=pid AND s.name=p->>'session_name';
    END IF;
    -- Any exception rolls back BOTH tables. No catch returning partial success.
    RETURN jsonb_build_object('success',true,'status',200,
        'applied_weight',w,'applied_scheme',new_scheme,'current_weight',w,'current_scheme',new_scheme);
END $fn$;
REVOKE ALL ON FUNCTION public.apply_progression(JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_progression(JSONB) TO service_role;
COMMIT;
