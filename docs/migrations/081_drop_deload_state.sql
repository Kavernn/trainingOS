-- =============================================================================
-- Migration 081 — DROP TABLE deload_state
-- =============================================================================
-- La migration 080 a créé deload_periods et reporté la décharge active (le cas
-- échéant). Le code backend (commit 4218baad) a basculé lecture + écriture
-- vers deload_periods. Vérifié en prod : /api/deload/status décode, dashboard
-- + Stats OK. Aucune lecture/écriture résiduelle (grep deload_state sur api/
-- et Models/ = 0 occurrence hors commentaires de migration).
--
-- Le DROP CASCADE n'est PAS nécessaire : aucune FK pointe vers deload_state
-- (table single-row id=1 isolée).
-- =============================================================================

DROP TABLE IF EXISTS public.deload_state;
