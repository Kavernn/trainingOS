-- 080_envelope_labels_action.sql
-- Labels d'enveloppes en langage d'action (feedback Vince 2026-07-15).
-- "Attaque dette" (jargon militaire) et "Variable" (mot vide) remplacés par
-- des libellés clairs. Aucun changement de schéma ni de clé — les
-- envelope_key ('attaque', 'variable') restent identiques, seul le
-- label affiché à l'utilisateur change.

BEGIN;

UPDATE budget_envelopes SET label = 'Dettes à rembourser' WHERE key = 'attaque';
UPDATE budget_envelopes SET label = 'Dépenses libres'      WHERE key = 'variable';

-- Vérification.
SELECT key, label FROM budget_envelopes
WHERE key IN ('attaque', 'variable')
ORDER BY key;

COMMIT;
