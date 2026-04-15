-- Migration 013: Scan étiquette nutritionnelle
-- Ajoute un champ source pour distinguer les entrées manuelles, recherche, et scan caméra.

ALTER TABLE nutrition_entries
    ADD COLUMN IF NOT EXISTS source TEXT DEFAULT 'manual';
