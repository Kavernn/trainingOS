-- 079_realign_fixes.sql
-- Réalignement du plan budget sur les fixes réels (source : liste Vince 2026-07-15).
-- Fixes réels 1 172,19 $/mois : hypothèque 900 + gaz 130 + vapo 80 + Claude 32,19 + Supabase 30.
-- Attaque recalculée pour boucler la paie 1 743,91 $ :
--   3 487,82 (paie×2) − 1 172,19 (fixes) − 400 (épicerie) − 250 (variable) = 1 665,63 $/mois.
-- Miroir dans api/budget_projection.py (PLANNED_ATTACK_BEFORE/AFTER) et
-- Views/Budget/BudgetLogSheet.swift (BudgetPlan) : voir le commit qui inclut ce SQL.

BEGIN;

UPDATE budget_envelopes SET limit_cents = 117219 WHERE key = 'fixes';
UPDATE budget_envelopes SET limit_cents = 166563 WHERE key = 'attaque';

-- Vérification : doit renvoyer fixes=117219, attaque=166563.
SELECT key, label, limit_cents
FROM budget_envelopes
WHERE key IN ('fixes', 'attaque')
ORDER BY key;

COMMIT;
