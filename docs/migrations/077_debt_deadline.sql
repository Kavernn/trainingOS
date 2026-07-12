-- 077_debt_deadline.sql
-- deadline réelle (date de départ) ; distincte de la projection.
-- NULL = pas de deadline. Déjà appliquée manuellement en prod le 2026-07-12.

ALTER TABLE debt_accounts ADD COLUMN deadline_date DATE NULL;
UPDATE debt_accounts SET deadline_date = '2026-09-12' WHERE key = 'fonds_voyage';
