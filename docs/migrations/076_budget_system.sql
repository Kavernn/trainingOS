-- 076_budget_system.sql
-- Module Budget : enveloppes, comptes de dette, logs monétaires.
-- Mono-utilisateur (pas de user_id, cohérent avec readiness_daily / cardio_logs).
-- Période = par paie (15 et min(30, dernier_jour) mensuel).
-- Tous montants en cents (integer). Dates MTL (YYYY-MM-DD).
-- Logs immuables : correction par contre-écriture (amount négatif + note obligatoire).

CREATE TABLE budget_envelopes (
  key         TEXT PRIMARY KEY,
  label       TEXT NOT NULL,
  limit_cents INTEGER NOT NULL CHECK (limit_cents > 0)
);

CREATE TABLE debt_accounts (
  key           TEXT PRIMARY KEY,
  label         TEXT NOT NULL,
  initial_cents INTEGER NOT NULL, -- solde de référence ; intérêts non modélisés — réconciliation manuelle future
  interest_rate NUMERIC(5,4),
  attack_order  INTEGER,
  is_savings    BOOLEAN NOT NULL DEFAULT FALSE,
  target_cents  INTEGER
);

CREATE TABLE money_logs (
  id           BIGSERIAL PRIMARY KEY,
  date         DATE NOT NULL,
  type         TEXT NOT NULL CHECK (type IN ('income','expense','debt_payment','fund_transfer')),
  amount_cents INTEGER NOT NULL,
  envelope_key TEXT REFERENCES budget_envelopes(key),
  debt_key     TEXT REFERENCES debt_accounts(key),
  note         TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX ux_money_logs_income_date
  ON money_logs (date) WHERE type = 'income';

INSERT INTO budget_envelopes (key, label, limit_cents) VALUES
  ('epicerie', 'Épicerie',      40000),
  ('variable', 'Variable',      25000),
  ('attaque',  'Attaque dette', 169500);

INSERT INTO debt_accounts (key, label, initial_cents, interest_rate, attack_order, is_savings, target_cents) VALUES
  ('decouvert',    'Découvert',    210000,  0.21, 1, FALSE, NULL),
  ('carte',        'Carte crédit', 1364000, 0.20, 2, FALSE, NULL),
  ('fonds_voyage', 'Fonds voyage', 0,       NULL, NULL, TRUE, 150000);

-- RLS activé par défaut sur Supabase : sans policies, PostgREST retourne vide
-- silencieusement (pas d'erreur, juste [] côté API). Pattern anon_all +
-- service_role_all sur les 3 tables budget.

ALTER TABLE budget_envelopes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON budget_envelopes
    FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "service_role_all" ON budget_envelopes
    FOR ALL TO service_role USING (true) WITH CHECK (true);

ALTER TABLE debt_accounts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON debt_accounts
    FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "service_role_all" ON debt_accounts
    FOR ALL TO service_role USING (true) WITH CHECK (true);

ALTER TABLE money_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON money_logs
    FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "service_role_all" ON money_logs
    FOR ALL TO service_role USING (true) WITH CHECK (true);
