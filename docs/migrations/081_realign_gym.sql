-- 081_realign_gym.sql
-- Réalignement bis du plan budget — intégration du gym (44 $/mois, fixe oublié
-- au premier passage 2026-07-15, découvert au deuxième pass 2026-07-16).
--
-- Fixes réels 1 172,19 + 44 = 1 216,19 $/mois.
-- Remboursement recalculé pour boucler la paie 1 743,91 $ :
--   3 487,82 (paie×2) − 1 216,19 (fixes) − 400 (épicerie) − 250 (variable)
--   = 1 621,63 $/mois de remboursement dette.
--
-- Miroir dans api/budget_projection.py (PLANNED_ATTACK_BEFORE/AFTER) et
-- Views/Budget/BudgetLogSheet.swift (BudgetPlan + fixesPerMonth) : voir
-- le commit qui inclut ce SQL.

BEGIN;

UPDATE budget_envelopes SET limit_cents = 121619 WHERE key = 'fixes';
UPDATE budget_envelopes SET limit_cents = 162163 WHERE key = 'attaque';

-- Vérification : doit renvoyer fixes=121619, attaque=162163.
SELECT key, label, limit_cents
FROM budget_envelopes
WHERE key IN ('fixes', 'attaque')
ORDER BY key;

COMMIT;
