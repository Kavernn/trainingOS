-- ============================================================================
-- Migration 101 — save_full_program_atomic (RPC plpgsql, transaction unique)
-- ============================================================================
--
-- Objectif : remplacer les N appels PostgREST séquentiels de save_full_program
-- (api/db_programs.py:476) par UNE RPC atomique. Avant, un échec en milieu de
-- parcours laissait la base dans un état partiel (ex: block upserté mais
-- exercices half-rewritten). Après, tout réussit ou rien n'est écrit (rollback
-- automatique sur exception dans une fonction plpgsql).
--
-- Contrat payload (identique sémantiquement au dict Python actuel mais avec
-- des tableaux pour préserver l'ordre — jsonb ne garantit pas l'ordre des clés
-- d'objet) :
--
--   p_program_id         UUID   — null = premier programme (compat get_default_program_id)
--   p_allow_empty_blocks BOOL   — bypass du garde "0 exos sur block non-vide" (intention explicite)
--   p_sessions           JSONB  — [{name, blocks:[{type, order, hiit_config, exercises:[{name, scheme}]}]}]
--   p_rename             JSONB  — null OU {"old_name","new_name"}. Renomme la row
--                                 exercises (même id, logs intacts) AVANT le pass
--                                 programme. Indispensable au flux rename de
--                                 /api/programme : le payload contient new_name
--                                 qui n'existe pas encore au catalogue sinon.
--
-- Ordre des sessions = position dans p_sessions. Ordre des blocks = champ
-- `order` (fallback 0). Ordre des exercices = position dans le tableau.
--
-- Retour : jsonb de compte rendu
--   {
--     "skipped_empty_blocks": [{"session_name", "block_type", "block_order", "existing_count"}, ...],
--     "renamed_exercise":     null | {"old_name","new_name","exercise_id"}
--   }
-- Le caller journalise et expose dans sa réponse HTTP (fin du silence).
--
-- Exercice manquant du catalogue : RAISE EXCEPTION. Après audit 2026-11, aucun
-- flux applicatif ne dépend de l'auto-création (add/replace workout_programs.py
-- appellent add_exercise AVANT save_full_program ; rename utilise désormais
-- p_rename). Lever = fail fast sur payload corrompu, pas de fantôme inventé
-- silencieux. Rollback intégral.
--
-- Rename merge non supporté : si new_name existe déjà au catalogue → RAISE
-- (unique_violation). Le flow actuel masquait le cas par un soft-delete
-- silencieux de l'ancienne row, orphelinant les exercise_logs. L'erreur
-- explicite force le caller à choisir (vrai merge = opération distincte).
--
-- Sécurité : SECURITY INVOKER (RLS appliquée). Tables program_sessions /
-- program_blocks / program_block_exercises / exercises ont toutes la policy
-- "anon_all" FOR ALL → anon peut exécuter via PostgREST. GRANT EXECUTE à
-- anon et service_role aligné sur ces mêmes droits.
--
-- Note sécurité (hors scope migration) : les policies "anon_all" donnent
-- écriture à quiconque détient la clé anon. Audit RLS + rotation clé
-- programmés comme chantier suivant (voir CLAUDE.md / tasks).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.save_full_program_atomic(
    p_program_id         UUID,
    p_allow_empty_blocks BOOLEAN,
    p_sessions           JSONB,
    p_rename             JSONB DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
AS $fn$
DECLARE
    v_program_id     UUID := p_program_id;
    v_session        JSONB;
    v_session_name   TEXT;
    v_session_id     UUID;
    v_session_order  INT := 0;
    v_block          JSONB;
    v_block_type     TEXT;
    v_block_order    INT;
    v_block_hiit     JSONB;
    v_block_id       UUID;
    v_exercises      JSONB;
    v_exercise       JSONB;
    v_ex_name        TEXT;
    v_ex_scheme      TEXT;
    v_ex_id          UUID;
    v_ex_order       INT;
    v_ex_ids         UUID[];
    v_existing_cnt   INT;
    v_skipped        JSONB := '[]'::jsonb;
    v_rename_report  JSONB := NULL;
    v_rename_old     TEXT;
    v_rename_new     TEXT;
    v_rename_id      UUID;
    -- Miroir api/blocks.py:REPS_BLOCKS (source unique). Les autres types
    -- (hiit, cardio) ne portent pas de program_block_exercises → skippés.
    v_reps_blocks    TEXT[] := ARRAY['strength','force','isolation','core','mobility','explosive','finisher'];
BEGIN
    -- Fallback premier programme (compat db_programs.get_default_program_id)
    IF v_program_id IS NULL THEN
        SELECT id INTO v_program_id
        FROM programs
        ORDER BY created_at NULLS LAST, id
        LIMIT 1;
    END IF;

    -- Étape 0 : rename catalogue (même id → logs intacts). AVANT le pass
    -- programme pour que les lookups `SELECT id FROM exercises WHERE name = new`
    -- réussissent dans la boucle principale.
    IF p_rename IS NOT NULL THEN
        v_rename_old := p_rename->>'old_name';
        v_rename_new := p_rename->>'new_name';
        IF v_rename_old IS NOT NULL AND v_rename_new IS NOT NULL
           AND length(v_rename_old) > 0 AND length(v_rename_new) > 0
           AND v_rename_old <> v_rename_new
        THEN
            -- Merge non supporté : si new existe déjà et <> old → erreur explicite
            IF EXISTS (
                SELECT 1 FROM exercises
                WHERE name = v_rename_new AND deleted_at IS NULL
            ) THEN
                RAISE EXCEPTION
                    'save_full_program_atomic: rename cible "%" déjà au catalogue (merge non supporté — opération distincte requise)',
                    v_rename_new USING ERRCODE = 'unique_violation';
            END IF;

            UPDATE exercises
            SET    name = v_rename_new
            WHERE  name = v_rename_old
              AND  deleted_at IS NULL
            RETURNING id INTO v_rename_id;

            IF v_rename_id IS NOT NULL THEN
                v_rename_report := jsonb_build_object(
                    'old_name',    v_rename_old,
                    'new_name',    v_rename_new,
                    'exercise_id', v_rename_id
                );
            END IF;
            -- Si v_rename_id IS NULL : l'ancienne row n'existait pas (déjà
            -- renommée ou absente) — silencieux, pas de raise. Le pass programme
            -- continuera à lever si new_name reste introuvable au catalogue.
        END IF;
    END IF;

    v_session_order := 0;
    FOR v_session IN
        SELECT value FROM jsonb_array_elements(COALESCE(p_sessions, '[]'::jsonb))
    LOOP
        v_session_name := v_session->>'name';
        IF v_session_name IS NULL OR length(v_session_name) = 0 THEN
            v_session_order := v_session_order + 1;
            CONTINUE;
        END IF;

        -- Upsert session (unique index program_id+name)
        INSERT INTO program_sessions (program_id, name, order_index)
        VALUES (v_program_id, v_session_name, v_session_order)
        ON CONFLICT (program_id, name)
        DO UPDATE SET order_index = EXCLUDED.order_index
        RETURNING id INTO v_session_id;

        -- Blocks triés par leur champ `order` (parité Python)
        FOR v_block IN
            SELECT value
            FROM jsonb_array_elements(COALESCE(v_session->'blocks', '[]'::jsonb)) AS t(value)
            ORDER BY COALESCE((value->>'order')::int, 0)
        LOOP
            v_block_type  := COALESCE(v_block->>'type', 'strength');
            v_block_order := COALESCE((v_block->>'order')::int, 0);
            v_block_hiit  := COALESCE(v_block->'hiit_config', '{}'::jsonb);

            SELECT id INTO v_block_id
            FROM program_blocks
            WHERE session_id = v_session_id
              AND type       = v_block_type
              AND order_index = v_block_order
            LIMIT 1;

            IF v_block_id IS NULL THEN
                INSERT INTO program_blocks (session_id, type, order_index, hiit_config)
                VALUES (v_session_id, v_block_type, v_block_order, v_block_hiit)
                RETURNING id INTO v_block_id;
            ELSE
                UPDATE program_blocks
                SET hiit_config = v_block_hiit
                WHERE id = v_block_id;
            END IF;

            -- Seuls les REPS_BLOCKS portent des exercises relationnels
            IF NOT (v_block_type = ANY (v_reps_blocks)) THEN
                CONTINUE;
            END IF;

            v_exercises := COALESCE(v_block->'exercises', '[]'::jsonb);

            -- Garde anti-wipe (miroir Python) : refuser 0 exos sur un block qui
            -- en avait N, sauf si l'appelant déclare l'intention (allow_empty_blocks).
            IF jsonb_array_length(v_exercises) = 0 THEN
                SELECT COUNT(*)::int INTO v_existing_cnt
                FROM program_block_exercises WHERE block_id = v_block_id;

                IF v_existing_cnt > 0 AND NOT COALESCE(p_allow_empty_blocks, FALSE) THEN
                    -- Skip explicite consigné dans le compte rendu (fin du silence)
                    v_skipped := v_skipped || jsonb_build_object(
                        'session_name', v_session_name,
                        'block_type',   v_block_type,
                        'block_order',  v_block_order,
                        'existing_count', v_existing_cnt
                    );
                    CONTINUE;
                END IF;

                DELETE FROM program_block_exercises WHERE block_id = v_block_id;
                CONTINUE;
            END IF;

            -- Bulk upsert + delete sélectif (parité pattern Python safety-ordered)
            v_ex_ids   := ARRAY[]::UUID[];
            v_ex_order := 0;
            FOR v_exercise IN
                SELECT value FROM jsonb_array_elements(v_exercises)
            LOOP
                v_ex_name   := v_exercise->>'name';
                v_ex_scheme := v_exercise->>'scheme';
                IF v_ex_name IS NULL OR length(v_ex_name) = 0 THEN
                    v_ex_order := v_ex_order + 1;
                    CONTINUE;
                END IF;

                SELECT id INTO v_ex_id FROM exercises WHERE name = v_ex_name LIMIT 1;
                IF v_ex_id IS NULL THEN
                    -- Audit 2026-11 : aucun flux ne dépend d'un auto-create ici
                    -- (add/replace workout_programs.py appellent add_exercise AVANT).
                    -- Un nom inconnu = payload corrompu → fail fast + rollback complet.
                    RAISE EXCEPTION
                        'save_full_program_atomic: exercise "%" introuvable dans le catalogue (session=%, block_type=%, block_order=%). Le caller doit créer l''exercice avant d''appeler la RPC.',
                        v_ex_name, v_session_name, v_block_type, v_block_order
                        USING ERRCODE = 'foreign_key_violation';
                END IF;

                INSERT INTO program_block_exercises (block_id, exercise_id, scheme, order_index)
                VALUES (v_block_id, v_ex_id, v_ex_scheme, v_ex_order)
                ON CONFLICT (block_id, exercise_id)
                DO UPDATE SET scheme      = EXCLUDED.scheme,
                              order_index = EXCLUDED.order_index;

                v_ex_ids   := v_ex_ids || v_ex_id;
                v_ex_order := v_ex_order + 1;
            END LOOP;

            -- Delete sélectif des exos qui ne sont plus dans la nouvelle liste.
            -- Exécuté après l'upsert → si l'upsert avait levé, on serait jamais
            -- arrivé ici et rien n'aurait été supprimé (atomicité fonction).
            DELETE FROM program_block_exercises
            WHERE block_id = v_block_id
              AND NOT (exercise_id = ANY (v_ex_ids));
        END LOOP;

        v_session_order := v_session_order + 1;
    END LOOP;

    -- Atomicité : une fonction plpgsql entière = une seule transaction.
    -- Toute exception non attrapée → rollback automatique de toutes les écritures
    -- (y compris le rename exercises de l'étape 0).
    RETURN jsonb_build_object(
        'skipped_empty_blocks', v_skipped,
        'renamed_exercise',     v_rename_report
    );
END;
$fn$;

-- Alignement droits avec policies "anon_all" des tables concernées.
GRANT EXECUTE ON FUNCTION public.save_full_program_atomic(UUID, BOOLEAN, JSONB, JSONB)
    TO anon, authenticated, service_role;
