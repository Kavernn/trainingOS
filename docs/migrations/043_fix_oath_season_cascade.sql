-- Migration 043 — ON DELETE CASCADE sur oath_recalls et season_snapshots
--
-- Problème : les FKs créées en migrations 034 et 035 n'ont pas de clause ON DELETE.
-- Comportement par défaut PostgreSQL = RESTRICT, ce qui rend impossible la suppression
-- d'un oath ou d'une season si des lignes enfants existent.
-- Incohérent avec le reste du schéma (exercise_logs, program_block_exercises → CASCADE).
--
-- Fix : DROP + ADD CONSTRAINT avec ON DELETE CASCADE.
-- Les noms de contraintes sont ceux générés automatiquement par PostgreSQL.

-- oath_recalls.oath_id → oaths.id
ALTER TABLE oath_recalls
    DROP CONSTRAINT IF EXISTS oath_recalls_oath_id_fkey,
    ADD CONSTRAINT oath_recalls_oath_id_fkey
        FOREIGN KEY (oath_id) REFERENCES oaths(id) ON DELETE CASCADE;

-- season_snapshots.season_id → seasons.id
ALTER TABLE season_snapshots
    DROP CONSTRAINT IF EXISTS season_snapshots_season_id_fkey,
    ADD CONSTRAINT season_snapshots_season_id_fkey
        FOREIGN KEY (season_id) REFERENCES seasons(id) ON DELETE CASCADE;

-- Marquer comme appliquée dans le tracker
INSERT INTO public.schema_migrations (version)
VALUES ('043_fix_oath_season_cascade')
ON CONFLICT (version) DO NOTHING;
