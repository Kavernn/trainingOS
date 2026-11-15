-- ============================================================================
-- Migration 102 — ROLLBACK Phase 2 : rétablit l'accès anon permissif
-- ============================================================================
--
-- Usage : à exécuter SEULEMENT si la Phase 2 (DROP all policies) casse quelque
-- chose en prod. Recrée une policy "anon_all FOR ALL TO anon USING (true)
-- WITH CHECK (true)" sur CHAQUE table de public ayant RLS activée.
--
-- Note : ce rollback restaure le NIVEAU D'ACCÈS (anon = full), pas forcément
-- les noms de policies originels. Avant Phase 2, certaines tables avaient
-- des policies nommées "allow_all", "allow_all_programs", "wr_*_allow_all",
-- "spirit_*_all", "oath_all", "seasons_all", "daily_brief_anon_all", etc.
-- Toutes avaient la même sémantique (FOR ALL TO anon USING (true)). Après
-- rollback, elles s'appelleront toutes "anon_all" — comportement identique,
-- noms harmonisés.
--
-- Pour un retour byte-exact, snapshoter AVANT Phase 2 :
--   SELECT 'CREATE POLICY ' || quote_ident(policyname)
--        || ' ON ' || quote_ident(schemaname) || '.' || quote_ident(tablename)
--        || ' AS '  || permissive
--        || ' FOR ' || cmd
--        || ' TO '  || array_to_string(roles, ', ')
--        || COALESCE(' USING ('     || qual     || ')', '')
--        || COALESCE(' WITH CHECK (' || with_check || ')', '')
--        || ';'
--   FROM pg_policies WHERE schemaname='public';
-- ============================================================================

DO $$
DECLARE
    tbl RECORD;
BEGIN
    FOR tbl IN
        SELECT tablename
        FROM pg_tables
        WHERE schemaname = 'public'
          AND rowsecurity = TRUE
        ORDER BY tablename
    LOOP
        -- Idempotent : skip si une policy anon_all existe déjà sur cette table.
        IF NOT EXISTS (
            SELECT 1 FROM pg_policies
            WHERE schemaname = 'public'
              AND tablename  = tbl.tablename
              AND policyname = 'anon_all'
        ) THEN
            EXECUTE format(
                'CREATE POLICY %I ON %I.%I FOR ALL TO anon USING (true) WITH CHECK (true)',
                'anon_all', 'public', tbl.tablename
            );
            RAISE NOTICE 'Recreated anon_all on public.%', tbl.tablename;
        END IF;
    END LOOP;
END $$;
