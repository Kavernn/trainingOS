-- 094_op0d_exercise_prs.sql — READ-ONLY
-- Pour chaque paire (dup + canon), liste toutes les lignes exercise_prs.
-- SELECT * pour voir toutes les colonnes (metric/type/valeur/date) sans hypothèse
-- sur le schéma. Le label pair_name + role permet de comparer dup vs canon côte à côte.
--
-- Lecture :
--   - Zéro ligne pour une paire → repoint UPDATE simple, rien à résoudre.
--   - Lignes du dup uniquement → UPDATE exercise_id sans conflit.
--   - Lignes des deux côtés SUR MÊME métrique → collision : garder le meilleur PR,
--     supprimer l'autre (à trancher après lecture du résultat).

WITH labelled(exercise_id, pair_name, role) AS (
  VALUES
    ('fc506d23-f991-490a-8e46-37dc38461943'::uuid, 'Pushdown',     'canon'),
    ('6f0a128f-d066-47b9-bcb8-dd3b798a232e'::uuid, 'Pushdown',     'dup'),
    ('10254163-84fd-4bd6-8187-132c40992e72'::uuid, 'Neck Curl',    'canon'),
    ('610b92d0-f003-4f25-b6ad-eff39574112a'::uuid, 'Neck Curl',    'dup'),
    ('b953ce24-0fe9-4180-ba98-919e90f99597'::uuid, 'Reverse Curl', 'canon'),
    ('62d0bf52-3564-489d-b877-1fda69c6fce1'::uuid, 'Reverse Curl', 'dup')
)
SELECT
  l.pair_name,
  l.role,
  ep.*
FROM labelled l
LEFT JOIN exercise_prs ep ON ep.exercise_id = l.exercise_id
ORDER BY l.pair_name, l.role, ep.exercise_id;
