-- 078_envelope_fixes.sql
-- Nouvelle enveloppe "Fixes" (loyer + hydro + cell + gym + abonnements) : 1143 $/mois.
-- Déjà appliquée manuellement en prod le 2026-07-12.

INSERT INTO budget_envelopes (key, label, limit_cents) VALUES
  ('fixes', 'Fixes', 114300);
