-- 079_money_logs_windfall.sql
-- Ajoute 'windfall' au CHECK de money_logs.type (revenu surprise, split 80/20
-- côté iOS ; balance compte, rythme mesuré non — cf budget_projection).
-- Additive : DROP + ADD sont la seule voie propre PostgreSQL pour un CHECK.
-- Aucune contrainte d'unicité (plusieurs windfalls le même jour légitimes).

ALTER TABLE money_logs DROP CONSTRAINT money_logs_type_check;
ALTER TABLE money_logs ADD CONSTRAINT money_logs_type_check
  CHECK (type IN ('income','expense','debt_payment','fund_transfer','windfall'));
