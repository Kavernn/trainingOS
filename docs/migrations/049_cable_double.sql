-- Migration 049 — Introduce cable_double equipment type
-- Bilateral cable exercises (each arm on independent cable).
-- Weight = per side; volume ×2 is automatic because iOS stores total weight (input × 2).
-- Historical logs are NOT touched — only exercises table is updated.

UPDATE exercises
SET type = 'cable_double'
WHERE name IN (
    'Cable Curl',
    'Cable Fly / Pec Dec',
    'Rear Delt Cable Fly'
);
