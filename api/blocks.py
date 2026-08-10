"""Workout block definitions and helpers.

A block represents a single training modality within a session:
  - "strength" : resistance/weight training
  - "hiit"     : high-intensity interval training
  - "cardio"   : steady-state or zone-based cardio

Sessions are composed of one or more independent, reorderable blocks.
A session may contain only one block type, any combination of two, or all three.
"""
from __future__ import annotations

BLOCK_TYPES = ("strength", "hiit", "cardio")

# Blocs qui portent des program_block_exercises avec scheme reps.
# hiit/cardio EXCLUS : ils utilisent hiit_config (colonne dédiée).
# Source unique — importée par db_programs (get_full_program, save_full_program).
REPS_BLOCKS = frozenset({
    "strength", "force", "isolation", "core",
    "mobility", "explosive", "finisher",
})


def make_strength_block(exercises: dict, order: int = 0) -> dict:
    """Create a strength training block with {exercise: scheme} exercises."""
    return {"type": "strength", "order": order, "exercises": dict(exercises)}


def make_hiit_block(hiit_config: dict | None = None, order: int = 0) -> dict:
    """Create a HIIT block. hiit_config holds sprint/rest/rounds/speed overrides."""
    return {"type": "hiit", "order": order, "hiit_config": dict(hiit_config or {})}


def make_cardio_block(cardio_config: dict | None = None, order: int = 0) -> dict:
    """Create a cardio block. cardio_config holds target_min, intensity, etc."""
    return {"type": "cardio", "order": order, "cardio_config": dict(cardio_config or {})}


def sorted_blocks(blocks: list) -> list:
    """Return blocks sorted by their 'order' field."""
    return sorted(blocks, key=lambda b: b.get("order", 0))


def get_block(blocks: list, block_type: str) -> dict | None:
    """Return the first block of the given type, or None."""
    return next((b for b in blocks if b.get("type") == block_type), None)


def get_strength_exercises(session_def: dict) -> dict:
    """Return exercises of ALL reps-blocks (REPS_BLOCKS) merged in block order.

    Blocs itérés par order_index croissant, dict.update() fusion : sur collision
    de nom inter-blocs, le dernier bloc (par order) gagne (déterministe).
    Python 3.7+ préserve l'ordre d'insertion → l'ordre d'affichage suit celui
    des blocs (mobility d'abord, core/finisher en dernier selon order_index).

    Legacy flat format {"ExerciseName": "scheme"} retourné tel quel.
    """
    if "blocks" not in session_def:
        return session_def
    merged: dict = {}
    for block in sorted(session_def["blocks"], key=lambda b: b.get("order", 0)):
        if block.get("type") in REPS_BLOCKS:
            merged.update(block.get("exercises", {}))
    return merged


def get_strength_exercise_ids(session_def: dict) -> dict:
    """Return {name: exercise_id} for ALL reps-blocks merged in block order.

    Symétrique de get_strength_exercises — même boucle, même ordre → clés
    identiques (invariant : même row exercises via join get_full_program).
    Consommé par les endpoints qui exposent exercise_ids pour que iOS mute
    par id, jamais par nom (doctrine étape 3b).
    """
    if "blocks" not in session_def:
        return {}
    merged: dict = {}
    for block in sorted(session_def["blocks"], key=lambda b: b.get("order", 0)):
        if block.get("type") in REPS_BLOCKS:
            merged.update(block.get("exercise_ids", {}))
    return merged


def upsert_block(blocks: list, new_block: dict) -> list:
    """Insert or replace a block by type. Preserves all other blocks."""
    btype = new_block["type"]
    others = [b for b in blocks if b.get("type") != btype]
    return others + [new_block]


def remove_block(blocks: list, block_type: str) -> list:
    """Remove all blocks of the given type."""
    return [b for b in blocks if b.get("type") != block_type]


def reorder_blocks(blocks: list, order: list) -> list:
    """Reorder blocks given a list of types in desired order.

    e.g. order=["strength", "hiit", "cardio"]
    Blocks not in the explicit list are appended at the end.
    """
    indexed = {b["type"]: b for b in blocks}
    result = []
    for i, btype in enumerate(order):
        if btype in indexed:
            result.append({**indexed.pop(btype), "order": i})
    for i, b in enumerate(indexed.values(), start=len(result)):
        result.append({**b, "order": i})
    return result
