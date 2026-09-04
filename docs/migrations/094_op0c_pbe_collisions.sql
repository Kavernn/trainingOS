-- 094_op0c_pbe_collisions.sql — READ-ONLY
-- Pour chaque paire (canon ← dup), liste les program_block_exercises du dup dont
-- le MÊME block_id contient déjà le canonique.
-- → Ces pbe violeraient l'UNIQUE (block_id, exercise_id) sur un UPDATE simple.
--   Elles doivent être DELETE (pbe redondant du dup) au lieu d'être repointées.
--
-- Zéro ligne = aucune collision. Sinon, liste des pbe concernés avec contexte
-- (program_id + session_id + block_id + schemes).

WITH pairs(pair_name, canon_id, dup_id) AS (
  VALUES
    ('Pushdown',     'fc506d23-f991-490a-8e46-37dc38461943'::uuid, '6f0a128f-d066-47b9-bcb8-dd3b798a232e'::uuid),
    ('Neck Curl',    '10254163-84fd-4bd6-8187-132c40992e72'::uuid, '610b92d0-f003-4f25-b6ad-eff39574112a'::uuid),
    ('Reverse Curl', 'b953ce24-0fe9-4180-ba98-919e90f99597'::uuid, '62d0bf52-3564-489d-b877-1fda69c6fce1'::uuid)
)
SELECT
  p.pair_name,
  pb.session_id       AS program_session_id,
  ps.program_id       AS program_id,
  pbe_dup.block_id    AS block_id,
  pbe_dup.id          AS dup_pbe_id,
  pbe_dup.scheme      AS dup_scheme,
  pbe_canon.id        AS canon_pbe_id,
  pbe_canon.scheme    AS canon_scheme
FROM pairs p
JOIN program_block_exercises pbe_dup
     ON pbe_dup.exercise_id = p.dup_id
JOIN program_block_exercises pbe_canon
     ON pbe_canon.exercise_id = p.canon_id
    AND pbe_canon.block_id    = pbe_dup.block_id
JOIN program_blocks pb   ON pb.id = pbe_dup.block_id
JOIN program_sessions ps ON ps.id = pb.session_id
ORDER BY p.pair_name, program_id, program_session_id, block_id;
