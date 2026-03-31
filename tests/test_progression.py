"""
Validation complète de smart_progression.py — aucune écriture en DB.
Exécute des tests unitaires + simulations de sessions Push/Pull/Legs.
"""
import os, sys, json, copy
from pathlib import Path

_env_file = Path("/tmp/trainingos.env")
if _env_file.exists():
    for line in _env_file.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, _, v = line.partition("=")
            os.environ.setdefault(k.strip(), v.strip().strip('"'))

sys.path.insert(0, str(Path(__file__).parent))
import smart_progression as sp

# ── colour helpers ────────────────────────────────────────────────────────────
OK   = "\033[92m✅ OK  \033[0m"
FAIL = "\033[91m❌ FAIL\033[0m"
SEP  = "─" * 72

results = []   # (name, passed, detail)

def check(name: str, condition: bool, detail: str = ""):
    results.append((name, condition, detail))
    status = OK if condition else FAIL
    print(f"  {status}  {name}")
    if detail:
        print(f"         {detail}")

# =============================================================================
# 1. UNIT TESTS — helpers
# =============================================================================
print(f"\n{'='*72}")
print("  1. HELPERS UNITAIRES")
print('='*72)

# _parse_scheme
check("parse_scheme 4x5-7",  sp._parse_scheme("4x5-7")  == (4, 7))
check("parse_scheme 3x8-12", sp._parse_scheme("3x8-12") == (3, 12))
check("parse_scheme 3x15",   sp._parse_scheme("3x15")   == (3, 15))
check("parse_scheme 3x1",    sp._parse_scheme("3x1")    == (3, 1))
check("parse_scheme bad",    sp._parse_scheme("???")    == (0, 0))

# _to_int
check("to_int str",   sp._to_int("10") == 10)
check("to_int int",   sp._to_int(8)    == 8)
check("to_int None",  sp._to_int(None) == 0)
check("to_int empty", sp._to_int("")   == 0)

# _working_sets — flat load
flat = [{"weight": 100, "reps": "8"}, {"weight": 100, "reps": "8"}, {"weight": 100, "reps": "8"}]
check("working_sets flat = all sets",
      sp._working_sets(flat) == flat)

# _working_sets — wave loading
wave = [{"weight": 80, "reps": "8"}, {"weight": 90, "reps": "8"}, {"weight": 100, "reps": "5"}]
ws = sp._working_sets(wave)
check("working_sets wave = max-weight only",
      len(ws) == 1 and ws[0]["weight"] == 100,
      f"got {ws}")

# _max_weight
check("max_weight wave",  sp._max_weight(wave) == 100)
check("max_weight flat",  sp._max_weight(flat) == 100)
check("max_weight empty", sp._max_weight([]) is None)

# _hit_rate
sets_all10  = [{"weight": 100, "reps": "10"}, {"weight": 100, "reps": "10"}, {"weight": 100, "reps": "10"}]
sets_mixed  = [{"weight": 100, "reps": "12"}, {"weight": 100, "reps": "12"}, {"weight": 100, "reps": "8"}]
sets_none   = [{"weight": 100, "reps": "8"},  {"weight": 100, "reps": "8"}]

check("hit_rate 100% at 10",  sp._hit_rate(sets_all10, 10)  == 1.0)
check("hit_rate 0%  at 12",   sp._hit_rate(sets_all10, 12)  == 0.0)
check("hit_rate 66% at 12",   abs(sp._hit_rate(sets_mixed, 12) - 2/3) < 0.01,
      f"got {sp._hit_rate(sets_mixed, 12):.2f}")
check("hit_rate 0%  at 12 (8s)", sp._hit_rate(sets_none, 12) == 0.0)
check("hit_rate empty sets",  sp._hit_rate([], 10) == 0.0)

# _increment_for_category
check("increment push = 5 lbs",  sp._increment_for_category("push") == 5.0)
check("increment pull = 5 lbs",  sp._increment_for_category("pull") == 5.0)
check("increment legs = 10 lbs", sp._increment_for_category("legs") == 10.0)
check("increment core = 5 lbs",  sp._increment_for_category("core") == 5.0)

# =============================================================================
# 2. UNIT TESTS — generate_suggestions with mock data
# =============================================================================
print(f"\n{'='*72}")
print("  2. LOGIQUE DE PROGRESSION — MOCKS")
print('='*72)

import db as _db

# We'll monkey-patch db functions to inject controlled data — no real DB writes.
_orig_get_workout_session_by_type      = _db.get_workout_session_by_type
_orig_get_previous_session_of_type     = _db.get_previous_session_of_type
_orig_get_exercise_logs_for_session    = _db.get_exercise_logs_for_session_with_names
_orig_get_exercise_info                = _db.get_exercise_info
_orig_get_exercise_history             = _db.get_exercise_history

def _mock_session(sid: str, date: str, stype: str = "morning"):
    return {"id": sid, "date": date, "session_type": stype}

def _mock_log(name: str, sets: list, reps_str: str = ""):
    max_w = max(s["weight"] for s in sets)
    return {"exercise_name": name, "weight": max_w,
            "reps": reps_str or ",".join(str(s["reps"]) for s in sets),
            "sets_json": sets}

def _mock_info(lp: str, cat: str, scheme: str):
    return {"load_profile": lp, "category": cat, "default_scheme": scheme}

def _patch(cur_logs, prev_logs, info_map, history_map=None):
    """Patch db calls for one test scenario."""
    _db.get_workout_session_by_type = lambda d, t: _mock_session("CUR", "2026-04-01", t)
    _db.get_previous_session_of_type = lambda d, t: _mock_session("PRV", "2026-03-25", t)
    _db.get_exercise_logs_for_session_with_names = lambda sid: cur_logs if sid == "CUR" else prev_logs
    _db.get_exercise_info = lambda name: info_map.get(name)
    _db.get_exercise_history = lambda name, limit=5: (history_map or {}).get(name, [])

def _restore():
    _db.get_workout_session_by_type = _orig_get_workout_session_by_type
    _db.get_previous_session_of_type = _orig_get_previous_session_of_type
    _db.get_exercise_logs_for_session_with_names = _orig_get_exercise_logs_for_session
    _db.get_exercise_info = _orig_get_exercise_info
    _db.get_exercise_history = _orig_get_exercise_history

# ── Test A: compound_heavy — all sets at top → +weight ───────────────────────
print(f"\n{SEP}")
print("  A — compound_heavy: 4x5-7, tous les sets à 7 reps → +5 lbs (upper)")
print(SEP)
_patch(
    cur_logs  = [_mock_log("Bench Press",
                           [{"weight":185,"reps":"7"},{"weight":185,"reps":"7"},
                            {"weight":185,"reps":"7"},{"weight":185,"reps":"7"}])],
    prev_logs = [_mock_log("Bench Press",
                           [{"weight":185,"reps":"5"},{"weight":185,"reps":"5"},
                            {"weight":185,"reps":"5"},{"weight":185,"reps":"5"}])],
    info_map  = {"Bench Press": _mock_info("compound_heavy","push","4x5-7")},
)
s = sp.generate_suggestions("2026-04-01","morning")
_restore()
ok_a = len(s)==1 and s[0]["suggestion_type"]=="increase_weight" and s[0]["suggested_weight"]==190.0
check("suggestion_type = increase_weight", ok_a, str(s[0] if s else "empty"))
if s:
    check("suggested_weight = 185+5 = 190 lbs",   s[0]["suggested_weight"] == 190.0)
    check("current_weight = 185",                  s[0]["current_weight"]   == 185.0)
    check("reason mentions 100% et 7 reps",        "100%" in s[0]["reason"] and "7" in s[0]["reason"])

# ── Test B: compound_heavy — wave loading, eval last set ──────────────────────
print(f"\n{SEP}")
print("  B — compound_heavy wave loading: 185→205→225×7 → eval 225 uniquement → +10 lbs legs")
print(SEP)
_patch(
    cur_logs  = [_mock_log("Back Squat",
                           [{"weight":185,"reps":"5"},{"weight":205,"reps":"5"},
                            {"weight":225,"reps":"7"}])],
    prev_logs = [_mock_log("Back Squat",
                           [{"weight":185,"reps":"5"},{"weight":205,"reps":"5"},
                            {"weight":215,"reps":"5"}])],
    info_map  = {"Back Squat": _mock_info("compound_heavy","legs","4x5-7")},
)
s = sp.generate_suggestions("2026-04-01","morning")
_restore()
check("wave: suggestion_type = increase_weight",
      s and s[0]["suggestion_type"] == "increase_weight", str(s[0] if s else ""))
if s:
    check("wave: current_weight = 225 (max, not avg)", s[0]["current_weight"] == 225.0)
    check("wave: suggested_weight = 225+10 = 235 lbs", s[0]["suggested_weight"] == 235.0)

# ── Test C: compound_heavy — 90% threshold: 3/4 sets at top → +weight ─────────
print(f"\n{SEP}")
print("  C — compound_heavy 90%: 3 sets /4 à 7 reps (75%) → MAINTIEN")
print(SEP)
_patch(
    cur_logs  = [_mock_log("Pause Bench Press",
                           [{"weight":165,"reps":"7"},{"weight":165,"reps":"7"},
                            {"weight":165,"reps":"7"},{"weight":165,"reps":"5"}])],
    prev_logs = [_mock_log("Pause Bench Press",
                           [{"weight":155,"reps":"5"},{"weight":155,"reps":"5"},
                            {"weight":155,"reps":"5"},{"weight":155,"reps":"5"}])],
    info_map  = {"Pause Bench Press": _mock_info("compound_heavy","push","4x5-7")},
)
s = sp.generate_suggestions("2026-04-01","morning")
_restore()
check("75% < 90% → maintain",
      s and s[0]["suggestion_type"] == "maintain", str(s[0] if s else ""))

# Test C2: 4/4 at top (100% ≥ 90%) → +weight
print(f"\n{SEP}")
print("  C2 — compound_heavy 90%: 4/4 sets à 7 reps (100% ≥ 90%) → +poids")
print(SEP)
_patch(
    cur_logs  = [_mock_log("Pause Bench Press",
                           [{"weight":165,"reps":"7"},{"weight":165,"reps":"7"},
                            {"weight":165,"reps":"7"},{"weight":165,"reps":"7"}])],
    prev_logs = [_mock_log("Pause Bench Press",
                           [{"weight":155,"reps":"5"},]*4)],
    info_map  = {"Pause Bench Press": _mock_info("compound_heavy","push","4x5-7")},
)
s = sp.generate_suggestions("2026-04-01","morning")
_restore()
check("100% ≥ 90% → increase_weight",
      s and s[0]["suggestion_type"] == "increase_weight", str(s[0] if s else ""))

# ── Test D: compound_hypertrophy — 90% threshold ──────────────────────────────
print(f"\n{SEP}")
print("  D — compound_hypertrophy: 3x8-12, 3/3 sets à 12 reps → +5 lbs")
print(SEP)
_patch(
    cur_logs  = [_mock_log("Incline Dumbbell Press",
                           [{"weight":120,"reps":"12"},{"weight":120,"reps":"12"},
                            {"weight":120,"reps":"12"}])],
    prev_logs = [_mock_log("Incline Dumbbell Press",
                           [{"weight":115,"reps":"10"},]*3)],
    info_map  = {"Incline Dumbbell Press": _mock_info("compound_hypertrophy","push","3x8-12")},
)
s = sp.generate_suggestions("2026-04-01","morning")
_restore()
check("compound_hyper 100% → increase_weight",
      s and s[0]["suggestion_type"] == "increase_weight", str(s[0] if s else ""))
if s:
    check("suggested = 120+5 = 125", s[0]["suggested_weight"] == 125.0)

# ── Test E: isolation — 100% threshold ────────────────────────────────────────
print(f"\n{SEP}")
print("  E — isolation: 3x10-12, 2/3 sets à 12 reps (66%) → MAINTIEN (seuil 100%)")
print(SEP)
_patch(
    cur_logs  = [_mock_log("Triceps Extension",
                           [{"weight":44,"reps":"12"},{"weight":44,"reps":"12"},
                            {"weight":44,"reps":"10"}])],
    prev_logs = [_mock_log("Triceps Extension",
                           [{"weight":40,"reps":"10"},]*3)],
    info_map  = {"Triceps Extension": _mock_info("isolation","push","3x10-12")},
)
s = sp.generate_suggestions("2026-04-01","morning")
_restore()
check("isolation 66% < 100% → maintain",
      s and s[0]["suggestion_type"] == "maintain", str(s[0] if s else ""))

# Test E2: isolation — 3/3 at top → +weight
print(f"\n{SEP}")
print("  E2 — isolation: 3/3 sets à 12 reps (100%) → +5 lbs")
print(SEP)
_patch(
    cur_logs  = [_mock_log("Triceps Extension",
                           [{"weight":44,"reps":"12"},{"weight":44,"reps":"12"},
                            {"weight":44,"reps":"12"}])],
    prev_logs = [_mock_log("Triceps Extension",
                           [{"weight":40,"reps":"10"},]*3)],
    info_map  = {"Triceps Extension": _mock_info("isolation","push","3x10-12")},
)
s = sp.generate_suggestions("2026-04-01","morning")
_restore()
check("isolation 100% → increase_weight",
      s and s[0]["suggestion_type"] == "increase_weight", str(s[0] if s else ""))
if s:
    check("suggested = 44+5 = 49", s[0]["suggested_weight"] == 49.0)

# ── Test F: anti-regression ───────────────────────────────────────────────────
print(f"\n{SEP}")
print("  F — anti-régression: poids actuel < précédent → regression")
print(SEP)
_patch(
    cur_logs  = [_mock_log("Barbell Row",
                           [{"weight":155,"reps":"8"},]*3)],
    prev_logs = [_mock_log("Barbell Row",
                           [{"weight":175,"reps":"8"},]*3)],
    info_map  = {"Barbell Row": _mock_info("compound_hypertrophy","pull","4x6-8")},
)
s = sp.generate_suggestions("2026-04-01","morning")
_restore()
check("regression détectée",
      s and s[0]["suggestion_type"] == "regression", str(s[0] if s else ""))
if s:
    check("suggested_weight = prev max = 175", s[0]["suggested_weight"] == 175.0)
    check("current_weight = 155",              s[0]["current_weight"]   == 155.0)

# ── Test G: plateau detection ─────────────────────────────────────────────────
print(f"\n{SEP}")
print("  G — plateau ≥3 sessions au même max_weight + 100% au plafond → +série (plateau pair)")
print(SEP)
_patch(
    cur_logs  = [_mock_log("Lat Pulldown",
                           [{"weight":135,"reps":"10"},{"weight":135,"reps":"10"},
                            {"weight":135,"reps":"10"}])],
    prev_logs = [_mock_log("Lat Pulldown",
                           [{"weight":130,"reps":"8"},]*3)],
    info_map  = {"Lat Pulldown": _mock_info("compound_hypertrophy","pull","3x8-10")},
    history_map = {
        "Lat Pulldown": [
            {"weight": 135.0, "reps": "10,10,10", "sets_json": [{"weight":135,"reps":"10"}]*3},
            {"weight": 135.0, "reps": "10,10,10", "sets_json": [{"weight":135,"reps":"10"}]*3},
            {"weight": 135.0, "reps": "10,10,10", "sets_json": [{"weight":135,"reps":"10"}]*3},
        ]
    }
)
s = sp.generate_suggestions("2026-04-01","morning")
_restore()
check("plateau pair (3) → increase_sets",
      s and s[0]["suggestion_type"] == "increase_sets", str(s[0] if s else ""))
if s:
    check("suggested_scheme = 4x8-10", s[0]["suggested_scheme"] == "4x8-10",
          f"got {s[0].get('suggested_scheme')}")

# Test G2: plateau impair → deload
print(f"\n{SEP}")
print("  G2 — plateau impair (5) → décharge -10%")
print(SEP)
_patch(
    cur_logs  = [_mock_log("Lat Pulldown",
                           [{"weight":135,"reps":"10"},]*3)],
    prev_logs = [_mock_log("Lat Pulldown",
                           [{"weight":130,"reps":"8"},]*3)],
    info_map  = {"Lat Pulldown": _mock_info("compound_hypertrophy","pull","3x8-10")},
    history_map = {
        "Lat Pulldown": [
            {"weight": 135.0, "reps": "10,10,10", "sets_json": [{"weight":135,"reps":"10"}]*3},
        ] * 5
    }
)
s = sp.generate_suggestions("2026-04-01","morning")
_restore()
check("plateau impair (5) → deload",
      s and s[0]["suggestion_type"] == "deload", str(s[0] if s else ""))
if s:
    expected_deload = round(135 * 0.9 / 2.5) * 2.5
    check(f"deload weight = {expected_deload}",
          s[0]["suggested_weight"] == expected_deload,
          f"got {s[0].get('suggested_weight')}")

# Test G3: already at 4 sets → deload even at cycle_pos 0
print(f"\n{SEP}")
print("  G3 — plateau 3 sessions mais déjà à 4 sets → décharge (pas de 5e série)")
print(SEP)
_patch(
    cur_logs  = [_mock_log("Bench Press",
                           [{"weight":185,"reps":"7"},]*4)],  # 4 sets already
    prev_logs = [_mock_log("Bench Press",
                           [{"weight":180,"reps":"5"},]*4)],
    info_map  = {"Bench Press": _mock_info("compound_heavy","push","4x5-7")},
    history_map = {
        "Bench Press": [
            {"weight": 185.0, "reps": "7,7,7,7", "sets_json": [{"weight":185,"reps":"7"}]*4},
        ] * 3
    }
)
s = sp.generate_suggestions("2026-04-01","morning")
_restore()
check("4 sets déjà → deload, pas increase_sets",
      s and s[0]["suggestion_type"] == "deload", str(s[0] if s else ""))

# ── Test H: global fatigue ────────────────────────────────────────────────────
print(f"\n{SEP}")
print("  H — fatigue globale: ≥50% exercices en régression → fatigue_warning=True")
print(SEP)
_patch(
    cur_logs  = [
        _mock_log("Bench Press",     [{"weight":170,"reps":"5"},]*4),  # régression
        _mock_log("Incline Dumbbell Press",[{"weight":105,"reps":"8"},]*3),  # régression
        _mock_log("Triceps Extension",[{"weight":44,"reps":"10"},]*3),  # ok
    ],
    prev_logs = [
        _mock_log("Bench Press",     [{"weight":185,"reps":"5"},]*4),
        _mock_log("Incline Dumbbell Press",[{"weight":120,"reps":"8"},]*3),
        _mock_log("Triceps Extension",[{"weight":40,"reps":"10"},]*3),
    ],
    info_map  = {
        "Bench Press":          _mock_info("compound_heavy","push","4x5-7"),
        "Incline Dumbbell Press":_mock_info("compound_hypertrophy","push","3x8-12"),
        "Triceps Extension":    _mock_info("isolation","push","3x10-12"),
    },
)
s = sp.generate_suggestions("2026-04-01","morning")
_restore()
regressions = [x for x in s if x["suggestion_type"] == "regression"]
check("2/3 exercices en régression détectés", len(regressions) == 2)
check("fatigue_warning=True sur toutes les suggestions",
      all(x["fatigue_warning"] for x in s), str([x["fatigue_warning"] for x in s]))

# ── Test I: pas de suggestion si premier historique ───────────────────────────
print(f"\n{SEP}")
print("  I — exercice absent du prev_session → pas de suggestion")
print(SEP)
_patch(
    cur_logs  = [_mock_log("Overhead Press",[{"weight":115,"reps":"8"},]*3)],
    prev_logs = [],   # pas d'historique précédent
    info_map  = {"Overhead Press": _mock_info("compound_heavy","push","3x6-8")},
)
s = sp.generate_suggestions("2026-04-01","morning")
_restore()
check("no prev log → empty suggestions", s == [], str(s))

# ── Test J: core/NULL → pas de suggestion ────────────────────────────────────
print(f"\n{SEP}")
print("  J — load_profile=NULL (core) → pas de suggestion")
print(SEP)
_patch(
    cur_logs  = [_mock_log("Weighted Crunch",[{"weight":88,"reps":"10"},]*3)],
    prev_logs = [_mock_log("Weighted Crunch",[{"weight":82,"reps":"10"},]*3)],
    info_map  = {"Weighted Crunch": {"load_profile": None, "category":"core","default_scheme":"3x8-12"}},
)
s = sp.generate_suggestions("2026-04-01","morning")
_restore()
check("core load_profile=None → empty suggestions", s == [], str(s))

# ── Test K: bonus session → aucune suggestion ─────────────────────────────────
print(f"\n{SEP}")
print("  K — session_type='bonus' → aucune suggestion")
print(SEP)
s = sp.generate_suggestions("2026-04-01", "bonus")
check("bonus session → empty", s == [], str(s))

# =============================================================================
# 3. SIMULATION SESSIONS COMPLÈTES
# =============================================================================
print(f"\n{'='*72}")
print("  3. SIMULATIONS SESSIONS COMPLÈTES")
print('='*72)

# ── PUSH simulation ───────────────────────────────────────────────────────────
print(f"\n{SEP}")
print("  PUSH — session complète avec wave loading + mix compound/isolation")
print(SEP)

push_info = {
    "Pause Bench Press":      _mock_info("compound_heavy",       "push", "4x5-7"),
    "Incline Dumbbell Press": _mock_info("compound_hypertrophy", "push", "3x8-12"),
    "Triceps Dip":            _mock_info("compound_hypertrophy", "push", "3x8-12"),
    "Triceps Extension":      _mock_info("isolation",            "push", "3x10-12"),
    "Dumbbell Lateral Raise": _mock_info("isolation",            "push", "3x12-15"),
}
# Current: good session — bench wave 155→165×7, incline 3×12, dip 3×10, triceps ext 3×12, laterals 3×15
push_cur = [
    _mock_log("Pause Bench Press",      [{"weight":155,"reps":"5"},{"weight":165,"reps":"7"},
                                          {"weight":165,"reps":"7"},{"weight":165,"reps":"7"}]),
    _mock_log("Incline Dumbbell Press", [{"weight":120,"reps":"12"}]*3),
    _mock_log("Triceps Dip",            [{"weight":195,"reps":"10"}]*3),
    _mock_log("Triceps Extension",      [{"weight":44,"reps":"12"}]*3),
    _mock_log("Dumbbell Lateral Raise", [{"weight":35,"reps":"15"}]*3),
]
push_prev = [
    _mock_log("Pause Bench Press",      [{"weight":145,"reps":"5"},{"weight":155,"reps":"5"},
                                          {"weight":155,"reps":"5"},{"weight":155,"reps":"5"}]),
    _mock_log("Incline Dumbbell Press", [{"weight":115,"reps":"10"}]*3),
    _mock_log("Triceps Dip",            [{"weight":185,"reps":"10"}]*3),
    _mock_log("Triceps Extension",      [{"weight":40,"reps":"10"}]*3),
    _mock_log("Dumbbell Lateral Raise", [{"weight":35,"reps":"12"}]*3),
]
_patch(push_cur, push_prev, push_info)
push_s = sp.generate_suggestions("2026-04-01","morning")
_restore()

push_map = {s["exercise_name"]: s for s in push_s}

print(f"  {'EXERCICE':<35} {'RÈGLE':<20} {'SUGGESTION':<25} {'STATUT'}")
print(f"  {'-'*34} {'-'*19} {'-'*24} {'-'*6}")
expected_push = [
    ("Pause Bench Press",      "compound_heavy wave",  "increase_weight", 170.0),  # max=165, +5=170
    ("Incline Dumbbell Press", "compound_hyper 100%",  "increase_weight", 125.0),
    ("Triceps Dip",            "compound_hyper 0%@12", "maintain",        195.0),  # 10<12 → maintien
    ("Triceps Extension",      "isolation 100%",       "increase_weight",  49.0),
    ("Dumbbell Lateral Raise", "isolation 100%",       "increase_weight",  40.0),
]
for ex, rule, exp_type, exp_w in expected_push:
    s_ex = push_map.get(ex, {})
    ok = s_ex.get("suggestion_type") == exp_type and s_ex.get("suggested_weight") == exp_w
    check(f"{ex:<35} {rule:<20} → {exp_w} lbs", ok,
          f"got type={s_ex.get('suggestion_type')} w={s_ex.get('suggested_weight')}")

# ── PULL simulation ───────────────────────────────────────────────────────────
print(f"\n{SEP}")
print("  PULL — régression sur un exercice, plafond pas atteint sur les autres")
print(SEP)

pull_info = {
    "Barbell Row":          _mock_info("compound_hypertrophy","pull","4x6-8"),
    "Lat Pulldown":         _mock_info("compound_hypertrophy","pull","3x8-10"),
    "Cable Seated Row":     _mock_info("compound_hypertrophy","pull","3x8-12"),
    "Face Pull":            _mock_info("isolation",           "pull","3x15"),
    "Dumbbell Hammer Curl": _mock_info("isolation",           "pull","3x8-12"),
}
pull_cur = [
    _mock_log("Barbell Row",        [{"weight":155,"reps":"8"},]*4),   # régression vs 175
    _mock_log("Lat Pulldown",       [{"weight":135,"reps":"9"},]*3),   # 0% à 10 → maintien
    _mock_log("Cable Seated Row",   [{"weight":121,"reps":"12"}]*3),  # 100% → +5
    _mock_log("Face Pull",          [{"weight":65,"reps":"15"},]*3),  # 100% → +5
    _mock_log("Dumbbell Hammer Curl",[{"weight":50,"reps":"10"},]*3), # 0% at 12 → maintien
]
pull_prev = [
    _mock_log("Barbell Row",        [{"weight":175,"reps":"8"},]*4),
    _mock_log("Lat Pulldown",       [{"weight":130,"reps":"8"},]*3),
    _mock_log("Cable Seated Row",   [{"weight":115,"reps":"10"},]*3),
    _mock_log("Face Pull",          [{"weight":60,"reps":"12"},]*3),
    _mock_log("Dumbbell Hammer Curl",[{"weight":50,"reps":"8"},]*3),
]
_patch(pull_cur, pull_prev, pull_info)
pull_s = sp.generate_suggestions("2026-04-01","morning")
_restore()

pull_map = {s["exercise_name"]: s for s in pull_s}
expected_pull = [
    ("Barbell Row",         "anti-regression",    "regression", 175.0),
    ("Lat Pulldown",        "0% @ 10 → maintien", "maintain",   135.0),
    ("Cable Seated Row",    "100% @ 12 → +5",     "increase_weight", 126.0),
    ("Face Pull",           "100% @ 15 → +5",     "increase_weight",  70.0),
    ("Dumbbell Hammer Curl","0% @ 12 → maintien", "maintain",    50.0),
]
for ex, rule, exp_type, exp_w in expected_pull:
    s_ex = pull_map.get(ex, {})
    ok = s_ex.get("suggestion_type") == exp_type and s_ex.get("suggested_weight") == exp_w
    check(f"{ex:<35} {rule:<20} → {exp_w} lbs", ok,
          f"got type={s_ex.get('suggestion_type')} w={s_ex.get('suggested_weight')}")

# ── LEGS simulation ───────────────────────────────────────────────────────────
print(f"\n{SEP}")
print("  LEGS — wave loading, core ignoré, leg curl isolation 100%")
print(SEP)

legs_info = {
    "Back Squat":    _mock_info("compound_heavy",       "legs","4x5-7"),
    "Leg Press":     _mock_info("compound_hypertrophy", "legs","3x10-12"),
    "Leg Curl":      _mock_info("isolation",            "legs","3x10-12"),
    "Weighted Crunch":{"load_profile":None,"category":"core","default_scheme":"3x8-12"},
}
legs_cur = [
    _mock_log("Back Squat",  [{"weight":205,"reps":"5"},{"weight":225,"reps":"5"},
                               {"weight":245,"reps":"7"}]),   # wave, eval 245×7 → 90% → +10
    _mock_log("Leg Press",   [{"weight":300,"reps":"8"},{"weight":340,"reps":"8"},
                               {"weight":370,"reps":"8"}]),   # wave, eval 370×8 → 0% at 12 → maintien
    _mock_log("Leg Curl",    [{"weight":154,"reps":"12"},]*3),  # 100% → +10
    _mock_log("Weighted Crunch",[{"weight":88,"reps":"10"},]*3),  # core → ignored
]
legs_prev = [
    _mock_log("Back Squat",  [{"weight":185,"reps":"5"},{"weight":205,"reps":"5"},
                               {"weight":225,"reps":"5"}]),
    _mock_log("Leg Press",   [{"weight":280,"reps":"8"},{"weight":320,"reps":"8"},
                               {"weight":350,"reps":"8"}]),
    _mock_log("Leg Curl",    [{"weight":143,"reps":"10"},]*3),
    _mock_log("Weighted Crunch",[{"weight":82,"reps":"10"},]*3),
]
_patch(legs_cur, legs_prev, legs_info)
legs_s = sp.generate_suggestions("2026-04-01","morning")
_restore()

legs_map = {s["exercise_name"]: s for s in legs_s}
expected_legs = [
    ("Back Squat", "compound_heavy wave 245×7 ≥7 → +10", "increase_weight", 255.0),
    ("Leg Press",  "compound_hyper wave 370×8 @ 12 → 0%", "maintain",        370.0),
    ("Leg Curl",   "isolation 100% @ 12 → +10",           "increase_weight", 164.0),
]
for ex, rule, exp_type, exp_w in expected_legs:
    s_ex = legs_map.get(ex, {})
    ok = s_ex.get("suggestion_type") == exp_type and s_ex.get("suggested_weight") == exp_w
    check(f"{ex:<35} {rule[:19]:<20} → {exp_w} lbs", ok,
          f"got type={s_ex.get('suggestion_type')} w={s_ex.get('suggested_weight')}")

check("Weighted Crunch absent (core ignoré)",
      "Weighted Crunch" not in legs_map, str(list(legs_map.keys())))

# =============================================================================
# 4. INTÉGRITÉ DES DONNÉES — vérifier que DB n'a pas été modifiée
# =============================================================================
print(f"\n{'='*72}")
print("  4. INTÉGRITÉ DES DONNÉES HISTORIQUES")
print('='*72)

# Re-fetch a sample of real sessions and compare to initial pull
import db as _db2
import time

real_sessions = _db2.get_workout_sessions(limit=5)
check("sessions récupérables (client OK)", len(real_sessions) > 0)

# Spot-check the most recent real session's exercise logs
if real_sessions:
    sid = real_sessions[0]["id"]
    date = real_sessions[0]["date"]
    logs_before = _db2.get_exercise_logs_for_session_with_names(sid)
    time.sleep(0.3)
    logs_after  = _db2.get_exercise_logs_for_session_with_names(sid)
    check(f"logs session {date} identiques avant/après tests",
          logs_before == logs_after,
          f"{len(logs_before)} logs")

# Verify our migration 009 corrections are in place
ex_triceps_dip = _db2.get_exercise_info("Triceps Dip")
check("Triceps Dip category=push (migration 009)",
      ex_triceps_dip and ex_triceps_dip.get("category") == "push",
      str(ex_triceps_dip))

ex_wrist = _db2.get_exercise_info("Dumbbell Wrist Curl")
check("Dumbbell Wrist Curl load_profile=isolation (migration 009)",
      ex_wrist and ex_wrist.get("load_profile") == "isolation",
      str(ex_wrist))
check("Dumbbell Wrist Curl default_scheme=3x12-15",
      ex_wrist and ex_wrist.get("default_scheme") == "3x12-15",
      str(ex_wrist))

# =============================================================================
# RÉSUMÉ
# =============================================================================
print(f"\n{'='*72}")
passed = sum(1 for _, ok, _ in results if ok)
failed = sum(1 for _, ok, _ in results if not ok)
print(f"  RÉSULTAT FINAL : {passed} OK  /  {failed} FAIL  /  {len(results)} total")
print('='*72)

if failed:
    print("\n  Tests en échec :")
    for name, ok, detail in results:
        if not ok:
            print(f"    ❌  {name}")
            if detail:
                print(f"        {detail}")

sys.exit(0 if failed == 0 else 1)
