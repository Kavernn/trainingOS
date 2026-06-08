"""muscle_classification.py — Rule-based classification suggestions for existing exercises.

Used by /api/exercises/classification_gaps to suggest muscle_group, muscle_specific,
and movement_pattern for exercises that still have only legacy muscles[] data.
"""
from __future__ import annotations

# French muscle_group → English muscles[] key (for fallback label when group missing)
_MUSCLES_TO_GROUP: dict[str, str] = {
    "chest":        "Pectoraux",
    "back":         "Dos",
    "lats":         "Dos",
    "traps":        "Trapèzes",
    "shoulders":    "Épaules",
    "deltoids":     "Épaules",
    "biceps":       "Biceps",
    "triceps":      "Triceps",
    "quads":        "Quadriceps",
    "quadriceps":   "Quadriceps",
    "hamstrings":   "Ischio-jambiers",
    "glutes":       "Fessiers",
    "calves":       "Mollets",
    "abs":          "Abdominaux",
    "core":         "Abdominaux",
    "forearms":     "Avant-bras",
}

# (lowercase_keyword, muscle_specific, movement_pattern_hint)
# First match in name (lowercased) wins for muscle_specific.
_NAME_RULES: list[tuple[str, str, str | None]] = [
    # ── Épaules ──────────────────────────────────────────────────────────────
    ("rear delt",          "Deltoïde postérieur",   "pull_horizontal"),
    ("face pull",          "Deltoïde postérieur",   "pull_horizontal"),
    ("reverse fly",        "Deltoïde postérieur",   "pull_horizontal"),
    ("reverse flye",       "Deltoïde postérieur",   "pull_horizontal"),
    ("rear fly",           "Deltoïde postérieur",   "pull_horizontal"),
    ("posterior delt",     "Deltoïde postérieur",   "pull_horizontal"),
    ("lateral raise",      "Deltoïde latéral",      None),
    ("side raise",         "Deltoïde latéral",      None),
    ("side lateral",       "Deltoïde latéral",      None),
    ("front raise",        "Deltoïde antérieur",    None),
    ("arnold",             "Deltoïde antérieur",    "push_vertical"),
    ("overhead press",     "Deltoïde antérieur",    "push_vertical"),
    ("shoulder press",     "Deltoïde antérieur",    "push_vertical"),
    ("military press",     "Deltoïde antérieur",    "push_vertical"),
    # ── Pectoraux ────────────────────────────────────────────────────────────
    ("incline",            "Chef claviculaire",     "push_horizontal"),
    ("decline",            "Chef sternal inférieur","push_horizontal"),
    ("cable fly",          "Pectoral majeur",       "push_horizontal"),
    ("cable flye",         "Pectoral majeur",       "push_horizontal"),
    ("pec deck",           "Pectoral majeur",       "push_horizontal"),
    ("chest fly",          "Pectoral majeur",       "push_horizontal"),
    ("chest flye",         "Pectoral majeur",       "push_horizontal"),
    ("crossover",          "Pectoral majeur",       "push_horizontal"),
    ("dips",               "Pectoral majeur",       "push_vertical"),
    # ── Dos ──────────────────────────────────────────────────────────────────
    ("pull-up",            "Grand dorsal",          "pull_vertical"),
    ("pullup",             "Grand dorsal",          "pull_vertical"),
    ("pull up",            "Grand dorsal",          "pull_vertical"),
    ("chin-up",            "Grand dorsal",          "pull_vertical"),
    ("chin up",            "Grand dorsal",          "pull_vertical"),
    ("chinup",             "Grand dorsal",          "pull_vertical"),
    ("lat pulldown",       "Grand dorsal",          "pull_vertical"),
    ("pulldown",           "Grand dorsal",          "pull_vertical"),
    ("straight arm",       "Grand dorsal",          "pull_vertical"),
    ("seated row",         "Rhomboïdes",            "pull_horizontal"),
    ("cable row",          "Rhomboïdes",            "pull_horizontal"),
    ("chest supported",    "Rhomboïdes",            "pull_horizontal"),
    ("bent over row",      "Grand dorsal",          "pull_horizontal"),
    ("bent-over row",      "Grand dorsal",          "pull_horizontal"),
    ("t-bar",              "Rhomboïdes",            "pull_horizontal"),
    ("t bar",              "Rhomboïdes",            "pull_horizontal"),
    ("deadlift",           "Érecteurs du rachis",   "hinge"),
    ("good morning",       "Érecteurs du rachis",   "hinge"),
    ("back extension",     "Érecteurs du rachis",   "hinge"),
    ("hyperextension",     "Érecteurs du rachis",   "hinge"),
    ("shrug",              "Trapèze supérieur",     None),
    # ── Jambes ───────────────────────────────────────────────────────────────
    ("squat",              "Quadriceps",            "squat"),
    ("leg press",          "Quadriceps",            "press_machine"),
    ("leg extension",      "Quadriceps",            "isolation"),
    ("hack squat",         "Quadriceps",            "squat"),
    ("lunge",              "Quadriceps",            "lunge"),
    ("split squat",        "Quadriceps",            "lunge"),
    ("step up",            "Quadriceps",            "lunge"),
    ("leg curl",           "Ischio-jambiers",       "isolation"),
    ("nordic",             "Ischio-jambiers",       "hinge"),
    ("romanian",           "Ischio-jambiers",       "hinge"),
    (" rdl ",              "Ischio-jambiers",       "hinge"),
    ("stiff leg",          "Ischio-jambiers",       "hinge"),
    ("hip thrust",         "Grand fessier",         "hinge"),
    ("glute bridge",       "Grand fessier",         "hinge"),
    ("hip abduction",      "Moyen fessier",         "isolation"),
    ("abductor",           "Moyen fessier",         "isolation"),
    ("calf raise",         "Gastrocnémien",         "isolation"),
    ("seated calf",        "Soléaire",              "isolation"),
    # ── Bras ─────────────────────────────────────────────────────────────────
    ("preacher curl",      "Biceps brachial",       "isolation"),
    ("concentration curl", "Biceps brachial",       "isolation"),
    ("incline curl",       "Biceps brachial",       "isolation"),
    ("hammer curl",        "Brachioradialis",       "isolation"),
    ("reverse curl",       "Brachioradialis",       "isolation"),
    ("curl",               "Biceps brachial",       "isolation"),
    ("skull crusher",      "Chef long du triceps",  "isolation"),
    ("skull",              "Chef long du triceps",  "isolation"),
    ("overhead ext",       "Chef long du triceps",  "isolation"),
    ("tricep ext",         "Triceps brachial",      "isolation"),
    ("pushdown",           "Triceps brachial",      "isolation"),
    ("push down",          "Triceps brachial",      "isolation"),
    ("kickback",           "Triceps brachial",      "isolation"),
    ("close grip",         "Triceps brachial",      "push_horizontal"),
    # ── Core ─────────────────────────────────────────────────────────────────
    ("crunch",             "Droit de l'abdomen",    "isolation"),
    ("sit-up",             "Droit de l'abdomen",    "isolation"),
    ("sit up",             "Droit de l'abdomen",    "isolation"),
    ("plank",              "Transverse",            "carry"),
    ("ab wheel",           "Droit de l'abdomen",    "isolation"),
    ("cable crunch",       "Droit de l'abdomen",    "isolation"),
    ("oblique",            "Obliques",              "rotation"),
    ("russian twist",      "Obliques",              "rotation"),
    ("pallof",             "Transverse",            "rotation"),
]


def suggest_classification(name: str, data: dict) -> dict | None:
    """Return {muscle_group, muscle_specific, movement_pattern} suggestion or None if nothing useful."""
    name_lower = " " + name.lower() + " "

    # Derive muscle_group from existing muscles[] if not already set
    current_mg = (data.get("muscle_group") or "").strip()
    if not current_mg:
        muscles = data.get("muscles") or []
        for m in muscles:
            mapped = _MUSCLES_TO_GROUP.get(m.lower().strip())
            if mapped:
                current_mg = mapped
                break

    current_ms = (data.get("muscle_specific") or "").strip()
    current_mp = (data.get("movement_pattern") or "").strip()

    suggested_ms: str | None = None
    suggested_mp: str | None = None

    for keyword, specific, pattern in _NAME_RULES:
        if keyword in name_lower:
            if not suggested_ms and not current_ms:
                suggested_ms = specific
            if not suggested_mp and not current_mp and pattern:
                suggested_mp = pattern
            break

    # Only return a suggestion if there's at least one new value to fill
    has_new_mg = bool(current_mg) and not (data.get("muscle_group") or "").strip()
    has_new_ms = bool(suggested_ms)
    has_new_mp = bool(suggested_mp)

    if not (has_new_mg or has_new_ms or has_new_mp):
        return None

    result: dict = {}
    if has_new_mg:
        result["muscle_group"] = current_mg
    if has_new_ms:
        result["muscle_specific"] = suggested_ms
    if has_new_mp:
        result["movement_pattern"] = suggested_mp
    return result
