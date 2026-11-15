-- ============================================================================
-- Migration 102 — Phase 2 : verrouillage RLS (DROP de toutes les policies anon
-- et service_role redondantes)
-- ============================================================================
--
-- Contexte : Phase 1 (commit c21fac2e + 0618cc4a) a basculé le backend sur
-- SUPABASE_SERVICE_ROLE_KEY. service_role bypasse RLS nativement → les
-- policies anon permissives ("anon_all FOR ALL TO anon USING (true)") sont
-- devenues inutiles ET dangereuses (quiconque détient la clé anon peut
-- toujours lire/écrire/supprimer).
--
-- Phase 2 : DROP de TOUTES les policies de public (anon ET service_role —
-- service_role est déjà bypass, les policies service_role sont redondantes).
-- RLS reste ENABLED sur chaque table → sans policy, anon = refus total
-- (SELECT retourne [], INSERT/UPDATE/DELETE refusés avec 42501). service_role
-- continue de fonctionner sans policy (bypass).
--
-- Retour arrière : docs/migrations/102_rls_rollback_phase_2.sql (recrée une
-- policy FOR ALL TO anon sur chaque table).
--
-- Après application : tester que
--   - le backend (service_role) : tout passe (reads + writes)
--   - un client anon direct : SELECT renvoie [], mutations renvoient 42501
-- ============================================================================

DO $$
DECLARE
    pol RECORD;
    n_dropped INT := 0;
BEGIN
    FOR pol IN
        SELECT schemaname, tablename, policyname
        FROM pg_policies
        WHERE schemaname = 'public'
        ORDER BY tablename, policyname
    LOOP
        EXECUTE format(
            'DROP POLICY IF EXISTS %I ON %I.%I',
            pol.policyname, pol.schemaname, pol.tablename
        );
        n_dropped := n_dropped + 1;
        RAISE NOTICE 'Dropped policy % on %.%',
                     pol.policyname, pol.schemaname, pol.tablename;
    END LOOP;
    RAISE NOTICE 'Phase 2 lockdown : % policies supprimées.', n_dropped;
END $$;

-- Vérification post-DROP : plus aucune policy en public.
-- À exécuter manuellement après la migration :
--   SELECT tablename, policyname FROM pg_policies WHERE schemaname='public';
--   -- Doit retourner 0 ligne.
--
-- Vérifier aussi que RLS reste ENABLED sur toutes les tables (sinon la
-- suppression de policies n'aurait aucun effet) :
--   SELECT tablename FROM pg_tables
--   WHERE schemaname='public' AND rowsecurity = FALSE;
--   -- Doit retourner 0 ligne (toutes les tables doivent avoir RLS actif).
