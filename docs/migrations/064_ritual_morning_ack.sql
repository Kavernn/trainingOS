-- Migration 064 — morning_ack dans daily_ritual
-- Acquittement matin : l'utilisateur confirme ou non avoir tenu son intention de la veille.
-- true = accompli, false = non accompli, null = pas d'intention hier soir (ou rituel matin non fait).
-- Nullable — zéro impact sur les données historiques.
ALTER TABLE daily_ritual
  ADD COLUMN IF NOT EXISTS morning_ack BOOLEAN;
