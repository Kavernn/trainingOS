-- 089_widen_program_blocks_type.sql
-- Élargit program_blocks.type pour accueillir la sémantique 6 blocs de
-- GymProgramme v4 (mobility, explosive, force, isolation, core, finisher).
-- Additive : conserve strength/hiit/cardio (utilisés par Locked In 2027 et
-- les scripts legacy — aucune ligne existante violée).
-- conname confirmé live = program_blocks_type_check.
-- ATTENTION consommateurs Python à patcher en DIFF 2 (avant toute donnée v4) :
--   api/db_programs.py:308 get_full_program  -> if btype=='strength' jette les
--     blocs non-strength dans la branche HIIT (exos perdus).
--   api/db_programs.py:367 get_session_supersets -> .eq("type","strength").
-- Cette migration est inerte tant qu'aucune ligne v4 n'existe : safe seule.

ALTER TABLE program_blocks DROP CONSTRAINT IF EXISTS program_blocks_type_check;
ALTER TABLE program_blocks ADD  CONSTRAINT program_blocks_type_check
  CHECK (type IN ('strength','hiit','cardio',
                  'mobility','explosive','force','isolation','core','finisher'));
