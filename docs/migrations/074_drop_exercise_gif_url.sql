-- Migration 074: drop gif_url column from exercises
-- Retrait complet des images d'exercices (catalogue jamais utilisé en pratique).
-- iOS (palier 1) et backend (palier 2) débranchés avant ce DROP.
-- 109 lignes avec gif_url non-NULL au moment du retrait — perte assumée.
ALTER TABLE public.exercises
    DROP COLUMN IF EXISTS gif_url;
