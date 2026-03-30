-- Migration 004: food_catalog
-- Catalogue d'aliments personnalisé (nom, macros par quantité de référence)
-- À appliquer dans Supabase SQL Editor

CREATE TABLE IF NOT EXISTS food_catalog (
    id        TEXT PRIMARY KEY,
    name      TEXT NOT NULL,
    ref_qty   REAL NOT NULL DEFAULT 100,
    ref_unit  TEXT NOT NULL DEFAULT 'g',
    calories  REAL NOT NULL DEFAULT 0,
    proteines REAL NOT NULL DEFAULT 0,
    glucides  REAL NOT NULL DEFAULT 0,
    lipides   REAL NOT NULL DEFAULT 0
);

ALTER TABLE food_catalog ENABLE ROW LEVEL SECURITY;

CREATE POLICY "anon_all" ON food_catalog
    FOR ALL TO anon
    USING (true)
    WITH CHECK (true);
