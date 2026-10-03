-- R11.0: deploy before the repaired API. No data backfill or inferred profiles.
BEGIN;
ALTER TABLE public.exercises ADD COLUMN IF NOT EXISTS progression_reference BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.exercises ADD COLUMN IF NOT EXISTS progression_schemes JSONB NOT NULL DEFAULT '{}';

-- Invoker rights preserve existing RLS. API only; clients cannot call the RPC directly.
CREATE OR REPLACE FUNCTION public.apply_progression(p JSONB) RETURNS JSONB
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE
    ex public.exercises%ROWTYPE;
    w NUMERIC;
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
    IF ex.current_weight IS DISTINCT FROM (p->>'expected_current_weight')::NUMERIC
        OR ex.default_scheme IS DISTINCT FROM p->>'expected_current_scheme' THEN
        RETURN jsonb_build_object('success',false,'status',409,'error','Recommandation devenue obsolète');
    END IF;
    w := CASE WHEN p->>'restore'='true' THEN (p->>'suggested_weight')::NUMERIC ELSE COALESCE((p->>'suggested_weight')::NUMERIC, ex.current_weight) END;
    new_scheme := CASE WHEN p->>'restore'='true' THEN p->>'suggested_scheme' ELSE COALESCE(p->>'suggested_scheme', ex.default_scheme) END;
    IF w < 0 OR w = 'NaN'::NUMERIC OR (new_scheme IS NOT NULL AND new_scheme !~ '^[1-9][0-9]*x[1-9][0-9]*(-[1-9][0-9]*)?s?$') THEN
        RETURN jsonb_build_object('success',false,'status',400,'error','Valeurs invalides');
    END IF;
    IF w IS NOT DISTINCT FROM ex.current_weight AND new_scheme IS NOT DISTINCT FROM ex.default_scheme THEN
        RETURN jsonb_build_object('success',false,'status',400,'error','Aucun changement');
    END IF;
    -- Lock prescriptions and reject divergent schemes rather than overwrite an
    -- independently edited programme. Undo uses the same expected pair.
    PERFORM pe.id FROM public.program_block_exercises pe
        JOIN public.program_blocks b ON b.id=pe.block_id
        JOIN public.program_sessions s ON s.id=b.session_id
        WHERE pe.exercise_id=ex.id AND s.program_id=pid AND s.name=p->>'session_name'
        FOR UPDATE OF pe;
    IF new_scheme IS DISTINCT FROM ex.default_scheme AND EXISTS (
        SELECT 1 FROM public.program_block_exercises pe
        JOIN public.program_blocks b ON b.id=pe.block_id
        JOIN public.program_sessions s ON s.id=b.session_id
        WHERE pe.exercise_id=ex.id AND s.program_id=pid AND s.name=p->>'session_name'
        AND pe.scheme IS DISTINCT FROM p->>'expected_current_scheme'
    ) THEN
        RETURN jsonb_build_object('success',false,'status',409,'error','Schéma du programme modifié');
    END IF;
    IF new_scheme IS DISTINCT FROM ex.default_scheme AND NOT EXISTS (
        SELECT 1 FROM public.program_block_exercises pe
        JOIN public.program_blocks b ON b.id=pe.block_id
        JOIN public.program_sessions s ON s.id=b.session_id
        WHERE pe.exercise_id=ex.id AND s.program_id=pid AND s.name=p->>'session_name'
    ) THEN
        RETURN jsonb_build_object('success',false,'status',409,'error','Prescription introuvable dans cette séance');
    END IF;
    UPDATE public.exercises SET current_weight=w, default_scheme=new_scheme,
        progression_reference=TRUE,
        progression_schemes=CASE WHEN new_scheme IS DISTINCT FROM ex.default_scheme
            THEN ex.progression_schemes || jsonb_build_object(pid::text || '/' || (p->>'session_name'),new_scheme)
            ELSE ex.progression_schemes END
        WHERE id=ex.id;
    IF new_scheme IS DISTINCT FROM ex.default_scheme THEN
        UPDATE public.program_block_exercises AS pe SET scheme=new_scheme
        FROM public.program_blocks AS b, public.program_sessions AS s
        WHERE pe.exercise_id=ex.id AND pe.block_id=b.id AND b.session_id=s.id
            AND s.program_id=pid AND s.name=p->>'session_name';
    END IF;
    -- Any exception rolls back BOTH tables. No catch returning partial success.
    RETURN jsonb_build_object('success',true,'status',200,
        'applied_weight',w,'applied_scheme',new_scheme,'current_weight',w,'current_scheme',new_scheme);
END $$;
REVOKE ALL ON FUNCTION public.apply_progression(JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_progression(JSONB) TO service_role;
COMMIT;
