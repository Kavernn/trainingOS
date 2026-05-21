-- Migration 047 — user_profile.active_program_id : TEXT → UUID + FK
--
-- Problème : migration 023 a ajouté active_program_id en type TEXT au lieu de UUID.
-- Il n'y a pas de FK vers programs(id), ce qui permet des références orphelines
-- (programme supprimé mais profil encore lié à cet ID).
--
-- Fix en 5 étapes (pattern safe — jamais DROP direct d'une colonne active) :
--   1. Ajouter colonne UUID intermédiaire
--   2. Migrer les données valides (filtre regex UUID pour éviter un cast error)
--   3. Ajouter la FK avec ON DELETE SET NULL (si programme supprimé → profil décroché)
--   4. Supprimer l'ancienne colonne TEXT
--   5. Renommer la colonne UUID en active_program_id
--
-- Données non-UUID dans active_program_id (si elles existent) sont perdues —
-- c'est acceptable car la colonne référence programs.id qui est toujours UUID.

-- Étape 1 : colonne UUID intermédiaire
ALTER TABLE user_profile
    ADD COLUMN IF NOT EXISTS active_program_uuid UUID;

-- Étape 2 : migration des données (seulement les valeurs qui sont des UUID valides)
UPDATE user_profile
SET active_program_uuid = active_program_id::UUID
WHERE active_program_id IS NOT NULL
  AND active_program_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

-- Étape 3 : FK — ON DELETE SET NULL pour ne pas invalider le profil si programme supprimé
ALTER TABLE user_profile
    ADD CONSTRAINT fk_user_active_program
        FOREIGN KEY (active_program_uuid) REFERENCES programs(id) ON DELETE SET NULL;

-- Étape 4 : supprimer l'ancienne colonne TEXT
ALTER TABLE user_profile
    DROP COLUMN IF EXISTS active_program_id;

-- Étape 5 : renommer
ALTER TABLE user_profile
    RENAME COLUMN active_program_uuid TO active_program_id;

-- Marquer comme appliquée dans le tracker
INSERT INTO public.schema_migrations (version)
VALUES ('047_fix_user_profile_active_program_id')
ON CONFLICT (version) DO NOTHING;
