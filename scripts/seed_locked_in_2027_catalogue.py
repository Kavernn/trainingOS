#!/usr/bin/env python3
"""
Seed catalogue Locked In 2027 (2026-08-03).

5 CRÉATIONS + 2 MUTATIONS d'exos existants (0 log historique, prouvé pour Farmers Walk).
Prérequis vérifiés : UNIQUE(name) confirmé (exercises_name_key), is_unilateral existe (087c).

VALEURS NEUVES introduites — VOULU (Zone-2 / Intervalles / Bloc plancher pelvien) :
    movement_pattern = 'Cardio'   (n'existait pas — première apparition)
    muscle_group     = 'Cardio'   (n'existait pas — première apparition)
    pattern (legacy) = 'cardio'   (n'existait pas — pour Zone-2 et Intervalles)

Idempotent : re-run = 0 changement.
    - upsert_exercise avec on_conflict="name" → INSERT ou UPDATE selon existence.
    - Farmers Walk : garde-fou pré-SELECT. Si "Farmer's Carry" existe déjà ET Farmers
      Walk absent → SKIP (re-run légitime). Si les deux existent → STOP (doublon fatal).
    - World's Greatest Stretch : UPDATE ciblé, idempotent par nature.

Catalogue seulement — aucun programme/séance créé, aucun log touché.

Run:
    python3 scripts/seed_locked_in_2027_catalogue.py [--dry-run]
"""

import os
import sys
import argparse
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
import db_core  # noqa: E402
import db_exercises  # noqa: E402


# ─────────────────────────────────────────────────────────────────────────────
# 5 CRÉATIONS (upsert on_conflict="name")
# ─────────────────────────────────────────────────────────────────────────────
CREATIONS: list[dict] = [
    {
        "name":              "Cable Woodchopper",
        "tracking_type":     "reps",
        "movement_pattern":  "Rotation",
        "pattern":           "core",
        "is_unilateral":     True,
        "weight_type":       "cable_single",
        "type":              "cable",
        "category":          "core",
        "level":             "intermediate",
        "load_profile":      "isolation",
        "muscle_group":      "Core",
        "muscle_specific":   "Obliques",
        "secondary_muscles": ["Abdominaux"],
        "muscles":           ["obliques", "abdominals"],
        "equipment":         ["cable"],
        "default_scheme":    "3x12",
        "tips":              "Pivote depuis le tronc, hanches stables. Le mouvement vient des obliques, pas des bras.",
        "increment":         5,
        "rest_seconds":      60,
    },
    {
        "name":              "Copenhagen / Side Plank",
        "tracking_type":     "time",
        "movement_pattern":  "Gainage",
        "pattern":           "core",
        "is_unilateral":     True,
        "weight_type":       "bodyweight",
        "type":              "bodyweight",
        "category":          "core",
        "level":             "advanced",
        "load_profile":      "isolation",
        "muscle_group":      "Core",
        "muscle_specific":   "Obliques",
        "secondary_muscles": ["Adducteurs"],
        "muscles":           ["obliques", "adductors", "abdominals"],
        "equipment":         ["bench"],
        "default_scheme":    "3x30s",
        "tips":              "Copenhagen : pied haut sur le banc, corps aligné. Trop dur → régresse en Side Plank genou au sol.",
        "increment":         0,
        "rest_seconds":      60,
    },
    {
        "name":              "Bloc plancher pelvien",
        "tracking_type":     "protocol",
        "movement_pattern":  "Cardio",       # NEUF
        "pattern":           "core",
        "is_unilateral":     False,
        "weight_type":       "bodyweight",
        "type":              "bodyweight",
        "category":          "core",
        "level":             "beginner",
        "load_profile":      "endurance",
        "muscle_group":      "Cardio",       # NEUF
        "muscle_specific":   "Plancher pelvien",
        "secondary_muscles": [],
        "muscles":           ["pelvic floor"],
        "equipment":         [],
        "default_scheme":    "",
        "tips":              "4 étapes : respiration diaphragmatique, contractions longues, flicks rapides, reverse kegels. ~5 min.",
        "increment":         0,
        "rest_seconds":      0,
    },
    {
        "name":              "Zone-2 (vélo/rameur)",
        "tracking_type":     "cardio",
        "movement_pattern":  "Cardio",       # NEUF
        "pattern":           "cardio",       # NEUF legacy
        "is_unilateral":     False,
        "weight_type":       "endurance",
        "type":              "machine",
        "category":          "cardio",
        "level":             "beginner",
        "load_profile":      "endurance",
        "muscle_group":      "Cardio",       # NEUF
        "muscle_specific":   "Système cardiovasculaire",
        "secondary_muscles": [],
        "muscles":           ["cardiovascular"],
        "equipment":         ["bike", "rower"],
        "default_scheme":    "1x30min",
        "tips":              "FC 60-70% max. Rythme conversationnel : tu dois pouvoir parler sans t'essouffler.",
        "increment":         0,
        "rest_seconds":      0,
    },
    {
        "name":              "Intervalles (VO2)",
        "tracking_type":     "interval",
        "movement_pattern":  "Cardio",       # NEUF
        "pattern":           "cardio",       # NEUF legacy
        "is_unilateral":     False,
        "weight_type":       "endurance",
        "type":              "machine",
        "category":          "cardio",
        "level":             "advanced",
        "load_profile":      "endurance",
        "muscle_group":      "Cardio",       # NEUF
        "muscle_specific":   "Système cardiovasculaire",
        "secondary_muscles": [],
        "muscles":           ["cardiovascular"],
        "equipment":         ["bike", "rower"],
        "default_scheme":    "8x30s",
        "tips":              "8 rounds : 30s à fond (VO2 max), 90s récup active. La récup complète est aussi importante que l'effort.",
        "increment":         0,
        "rest_seconds":      90,
    },
]

# ─────────────────────────────────────────────────────────────────────────────
# 2 MUTATIONS (exos existants — 0 log historique pour Farmers Walk, prouvé)
# ─────────────────────────────────────────────────────────────────────────────
FARMERS_OLD  = "Farmers Walk"
FARMERS_NEW  = "Farmer's Carry"
STRETCH_NAME = "World's Greatest Stretch"


def run(dry_run: bool) -> int:
    c = db_core._client
    if c is None:
        print("ERROR: db_core._client is None (OFFLINE ou env manquants).")
        return 1

    # === Preuve pré-seed ===
    resp = c.table("exercises").select("id", count="exact").is_("deleted_at", "null").execute()
    pre_count = resp.count
    print(f"[pré-seed] count actifs = {pre_count}   (attendu 127 avant premier run ; 132 sur re-run)")

    if dry_run:
        print("\n[DRY RUN] Aucune écriture. Voici ce qui serait fait :\n")
        for row in CREATIONS:
            print(f"  UPSERT  name={row['name']!r:30s}  tt={row['tracking_type']:9s} mp={row['movement_pattern']!r}")
        print(f"\n  GUARD   SELECT id WHERE name={FARMERS_NEW!r} AND deleted_at IS NULL")
        print(f"          si ≥1 ET {FARMERS_OLD!r} existe aussi → STOP (doublon fatal)")
        print(f"  UPDATE  {FARMERS_OLD!r} → name={FARMERS_NEW!r}, tt='carry', mp='Carry', pattern='carry'")
        print(f"  UPDATE  {STRETCH_NAME!r} → tt='time', mp='Gainage', pattern='isolation'")
        return 0

    # === PARTIE 1 — 5 CRÉATIONS (upsert on_conflict="name", idempotent) ===
    print("\n[PARTIE 1] Créations (upsert on_conflict=\"name\") :")
    for row in CREATIONS:
        saved = db_exercises.upsert_exercise(row)
        eid = saved.get("id") if isinstance(saved, dict) else None
        print(f"  UPSERT {row['name']!r:32s} → id={eid}")

    # === PARTIE 2 — GARDE-FOU + MUTATION Farmers Walk ===
    print("\n[PARTIE 2] Rename Farmers Walk → Farmer's Carry (avec garde-fou) :")
    guard = c.table("exercises").select("id").eq("name", FARMERS_NEW).is_("deleted_at", "null").execute()
    if guard.data:
        # "Farmer's Carry" existe déjà — soit re-run légitime, soit conflit.
        old = c.table("exercises").select("id").eq("name", FARMERS_OLD).is_("deleted_at", "null").execute()
        if old.data:
            print(f"  STOP: {FARMERS_NEW!r} et {FARMERS_OLD!r} coexistent — doublon fatal. Vince tranche.")
            return 2
        print(f"  SKIP: rename déjà appliqué (re-run idempotent).")
    else:
        upd = c.table("exercises").update({
            "name":             FARMERS_NEW,
            "tracking_type":    "carry",
            "movement_pattern": "Carry",
            "pattern":          "carry",
        }).eq("name", FARMERS_OLD).is_("deleted_at", "null").execute()
        if not upd.data:
            print(f"  WARNING: aucun row {FARMERS_OLD!r} trouvé — rien à renommer.")
        else:
            print(f"  RENAME {FARMERS_OLD!r} → {FARMERS_NEW!r} (+ tracking_type='carry')")

    # === PARTIE 3 — MUTATION World's Greatest Stretch (pas de rename, idempotent) ===
    print("\n[PARTIE 3] Mutation World's Greatest Stretch :")
    upd = c.table("exercises").update({
        "tracking_type":    "time",
        "movement_pattern": "Gainage",
        "pattern":          "isolation",
    }).eq("name", STRETCH_NAME).is_("deleted_at", "null").execute()
    if not upd.data:
        print(f"  WARNING: {STRETCH_NAME!r} introuvable — mutation non appliquée.")
    else:
        print(f"  UPDATE {STRETCH_NAME!r} → tt='time', mp='Gainage', pattern='isolation'")

    # === Preuves post-seed ===
    print("\n[preuves post-seed] :")
    resp = c.table("exercises").select("id", count="exact").is_("deleted_at", "null").execute()
    post_count = resp.count
    delta = post_count - pre_count
    print(f"  count actifs = {post_count}  (delta = +{delta}, attendu +5 si premier run, +0 si re-run)")

    all_names = [row["name"] for row in CREATIONS] + [FARMERS_NEW, STRETCH_NAME]
    verify = c.table("exercises").select(
        "name,tracking_type,movement_pattern,muscle_group,is_unilateral"
    ).in_("name", all_names).is_("deleted_at", "null").execute()
    found = {row["name"]: row for row in (verify.data or [])}
    print(f"  vérif 7 exos : {len(found)}/7 trouvés")
    for n in all_names:
        row = found.get(n)
        if not row:
            print(f"    MISSING {n!r}")
        else:
            print(f"    OK {n!r:32s} tt={row['tracking_type']:9s} mp={row.get('movement_pattern')!r:12s} mg={row.get('muscle_group')!r:10s} unilat={row.get('is_unilateral')}")

    fw_check = c.table("exercises").select("id").eq(
        "name", FARMERS_OLD
    ).is_("deleted_at", "null").execute()
    if fw_check.data:
        print(f"  WARNING: {FARMERS_OLD!r} EXISTE ENCORE (rename raté ou re-créé).")
    else:
        print(f"  OK: {FARMERS_OLD!r} absent (bien renommé).")

    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="Affiche sans écrire.")
    args = ap.parse_args()
    sys.exit(run(dry_run=args.dry_run))
