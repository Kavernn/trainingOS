-- 082_money_logs_category_key.sql
-- Ajoute money_logs.category_key TEXT NULL — le cœur du G/L Vince.
-- Chaque dollar classé à la saisie via un plan de comptes stable
-- (BudgetPlan.categoriesByEnvelope iOS, source unique). L'enveloppe s'infère
-- de la catégorie côté iOS ; le backend accepte et persiste sans valider la
-- valeur de la clé (plan de comptes stocké en front, migrable sans DDL).
--
-- NULL sur les logs historiques — aucun backfill, aucune donnée touchée.
-- Les logs post-migration porteront category_key ; les rapports futurs
-- filtreront proprement (WHERE category_key IS NOT NULL).
--
-- Backend enforce que category_key est réservé aux dépenses (rejet 400 si
-- fourni avec type debt_payment/fund_transfer/windfall).

BEGIN;

ALTER TABLE money_logs ADD COLUMN category_key TEXT NULL;

-- Vérif structure : la colonne existe, NULL par défaut, aucune donnée
-- historique modifiée.
SELECT COUNT(*) AS logs_total,
       COUNT(category_key) AS logs_avec_categorie
FROM money_logs;
-- Attendu : logs_total = N (nombre existant), logs_avec_categorie = 0.

COMMIT;
