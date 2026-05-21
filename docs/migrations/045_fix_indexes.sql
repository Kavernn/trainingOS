-- Migration 045 — Index manquants identifiés lors de l'audit 2026-05-20
--
-- program_sessions.program_id : colonne FK (REFERENCES programs.id) sans index.
-- Toute requête SELECT ... JOIN programs ON program_sessions.program_id = programs.id
-- force un sequential scan sur program_sessions. Impact direct sur le chargement
-- du programme actif (appel fréquent à chaque ouverture de l'app).

CREATE INDEX IF NOT EXISTS idx_program_sessions_program_id
    ON program_sessions (program_id);

-- Marquer comme appliquée dans le tracker
INSERT INTO public.schema_migrations (version)
VALUES ('045_fix_indexes')
ON CONFLICT (version) DO NOTHING;
