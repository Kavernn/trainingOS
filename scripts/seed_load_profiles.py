#!/usr/bin/env python3
"""
Populate missing load_profile for exercises that fall back to score=50 in workout_dna.

Valid load_profile values (from _LOAD_SCORE in workout_dna.py):
  compound_heavy       → 80  (low-rep strength compounds)
  compound_hypertrophy → 55  (moderate-rep compounds / machines)
  isolation            → 35  (single-joint)
  bodyweight           → 45  (BW or partial-load)
  cardio               → 20

Run:
    python3 scripts/seed_load_profiles.py [--dry-run]
"""

import os, sys, argparse

from pathlib import Path

def _load_env() -> None:
    root = Path(__file__).parent.parent
    for f in [".env", ".env.local"]:
        p = root / f
        if p.exists():
            for line in p.read_text().splitlines():
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, _, v = line.partition("=")
                os.environ.setdefault(k.strip(), v.strip().strip('"'))

_load_env()

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))
import db_core

PROFILES: dict[str, str] = {
    # ── compound_heavy ──────────────────────────────────────────────────────
    "Back Squat":               "compound_heavy",
    "Pull-up / Weighted":       "compound_heavy",

    # ── compound_hypertrophy ────────────────────────────────────────────────
    "Incline DB Press":         "compound_hypertrophy",
    "Hack Squat":               "compound_hypertrophy",
    "Dips":                     "compound_hypertrophy",
    "Leg Press":                "compound_hypertrophy",
    "Incline Barbell Press":    "compound_hypertrophy",
    "Flat DB Press":            "compound_hypertrophy",
    "Hip Thrust":               "compound_hypertrophy",
    "Chest-Supported DB Row":   "compound_hypertrophy",
    "Cable Pull-Through":       "compound_hypertrophy",
    "Goblet Squat":             "compound_hypertrophy",
    "Single-Arm DB Row":        "compound_hypertrophy",
    "Seated Cable Row":         "compound_hypertrophy",
    "Nordic Curl":              "compound_hypertrophy",
    "Bulgarian Split Squat":    "compound_hypertrophy",
    "Seated Z Press":           "compound_hypertrophy",

    # ── isolation ───────────────────────────────────────────────────────────
    "Weighted Crunch":          "isolation",
    "Abductor machine":         "isolation",
    "Unilateral lateral raises":"isolation",
    "Overhead Triceps Extension":"isolation",
    "Machine Rear Delt Flys":   "isolation",
    "Lateral Raise":            "isolation",
    "Leg Extension":            "isolation",
    "Lying Leg Curl":           "isolation",
    "Standing Calf Raise":      "isolation",
    "Spider Curl":              "isolation",
    "Tricep Pushdown":          "isolation",
    "Rear Delt Fly":            "isolation",
    "Rear Delt Cable Fly":      "isolation",
    "Overhead Tricep Ext.":     "isolation",
    "Cable Fly / Pec Dec":      "isolation",
    "Incline DB Curl":          "isolation",
    "EZ Bar Curl":              "isolation",
    "Sissy Squat":              "isolation",
    "Seated Calf Raise":        "isolation",
    "Barbell Shrug":            "isolation",
    "Hanging Leg Raise":        "isolation",
    "Abs wheel":                "isolation",

    # Deadhang : already "endurance" in DB — leave as-is
}


def run(dry_run: bool = False) -> None:
    client = db_core._client
    if client is None:
        print("ERROR: Supabase client not initialized")
        sys.exit(1)

    # Fetch existing load_profile for all target exercises
    names = list(PROFILES.keys())
    resp = (
        client.table("exercises")
        .select("name, load_profile")
        .in_("name", names)
        .is_("deleted_at", "null")
        .execute()
    )
    existing = {row["name"]: row.get("load_profile") for row in (resp.data or [])}

    missing_in_db = [n for n in names if n not in existing]
    if missing_in_db:
        print(f"⚠️  {len(missing_in_db)} exercice(s) introuvables en DB (nom exact incorrect) :")
        for n in missing_in_db:
            print(f"   - {n}")

    updates = [
        {"name": name, "load_profile": profile}
        for name, profile in PROFILES.items()
        if name in existing and existing[name] != profile
    ]
    already_ok = [
        name for name, profile in PROFILES.items()
        if name in existing and existing[name] == profile
    ]

    print(f"\n✅ Déjà corrects  : {len(already_ok)}")
    print(f"🔧 À mettre à jour : {len(updates)}")

    if not updates:
        print("Rien à faire.")
        return

    for u in updates:
        print(f"  {u['name']:45s}  →  {existing.get(u['name']) or '(vide)':25s}  →  {u['load_profile']}")

    if dry_run:
        print("\n[dry-run] Aucune écriture.")
        return

    ok = err = 0
    for u in updates:
        try:
            client.table("exercises").update({"load_profile": u["load_profile"]}).eq("name", u["name"]).execute()
            ok += 1
        except Exception as e:
            print(f"  ERROR {u['name']}: {e}")
            err += 1

    print(f"\n✅ {ok} mis à jour, ❌ {err} erreurs")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    run(dry_run=args.dry_run)
