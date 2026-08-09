#!/usr/bin/env python3
"""
Seed programme 'GymProgramme v4' (2026-08-09).

12 sessions (Lun→Ven + Dim, AM/PM, Samedi repos), 30 blocs typés
(mobility/explosive/force/isolation/core/finisher), 75 program_block_exercises.

Ce seed CRÉE le programme en DORMANCE. Locked In 2027 reste actif.
Ni weekly_schedule ni user_profile.active_program_id ne sont touchés — c'est
le rôle du diff 5.

Idempotent :
    - P0b : programme existant → REUSE son id, save_full_program remplace le contenu.
    - save_full_program : on_conflict(program_id,name) sur sessions ; match
      (session_id,type,order_index) sur blocks ; DELETE+INSERT sur block_exercises.

HARD GATE preflight : les noms d'exos du payload sont vérifiés live contre
exercises (deleted_at IS NULL). Un miss → STOP code 2, aucune écriture.
Prévient l'auto-création silencieuse de doublon NULL par save_full_program
(api/db_programs.py:535-547).

STEP 0 : si un programme v4 existe déjà, snapshot JSON complet dans
scripts/backups/gymprogramme_v4_<horodaté>.json.

Codes de sortie :
    0 succès
    1 client None (OFFLINE / env manquants)
    2 preflight fail (nom absent ou soft-deleted)
    3 INSERT programs fail
    4 doublon intra-bloc
    5 save_full_program retour False
    6 vérif post-save incohérente
    7 backup fail

Run:
    python3 scripts/seed_gymprogramme_v4.py [--dry-run]
"""

import os
import sys
import json
import argparse
from datetime import datetime
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
import db_core        # noqa: E402
import db_programs    # noqa: E402


PROGRAM_NAME = "GymProgramme v4"
BACKUP_DIR = Path(__file__).parent / "backups"


# ─────────────────────────────────────────────────────────────────────────────
# SPEC VERBATIM — 12 sessions, 30 blocs typés, 75 exos.
# Format : (session_name, [(block_type, block_order, [(exo, scheme), ...]), ...])
# Ordre des exos = ordre listé (→ order_index via insertion dans le dict Py 3.7+).
# ─────────────────────────────────────────────────────────────────────────────
SESSIONS: list[tuple[str, list[tuple[str, int, list[tuple[str, str]]]]]] = [
    ("Lundi AM — Push A", [
        ("mobility", 0, [
            ("Thoracic Extension + Open Book",     "2x8"),
            ("Band Shoulder CARs",                 "2x5/côté"),
        ]),
        ("explosive", 1, [
            ("Medicine Ball Chest Pass",           "4x5"),
        ]),
        ("force", 2, [
            ("Bench Press",                        "4x5-8"),
            ("Incline DB Press",                   "4x6-10"),
            ("Dips",                               "3x6-10"),
        ]),
    ]),
    ("Lundi PM — Push A", [
        ("isolation", 0, [
            ("Cable Fly / Pec Dec",                "5x10-15"),
            ("Incline Cable Fly",                  "3x12-15"),
            ("Cable Crossover",                    "3x12-15"),
            ("Triceps Pushdown",                   "4x10-15"),
            ("Overhead Triceps Extension",         "3x10-15"),
        ]),
        ("core", 1, [
            ("Pallof Press",                       "3x10-12/côté"),
        ]),
    ]),
    ("Mardi AM — Pull A", [
        ("mobility", 0, [
            ("World's Greatest Stretch",           "3x5/côté"),
            ("Cat-Cow + Thoracic Rotation",        "2x8"),
        ]),
        ("explosive", 1, [
            ("Barbell Jump Shrug",                 "4x3"),
        ]),
        ("force", 2, [
            ("Pull-Up",                            "4x5-8"),
            ("Barbell Row",                        "4x6-8"),
            ("T-Bar Row",                          "3x6-10"),
        ]),
    ]),
    ("Mardi PM — Pull A", [
        ("isolation", 0, [
            ("Seated Cable Row",                   "4x10-12"),
            ("Chest-Supported DB Row",             "3x10-12"),
            ("Barbell Curl",                       "4x8-12"),
            ("Incline DB Curl",                    "3x10-15"),
            ("Face Pull",                          "3x15"),
        ]),
        ("finisher", 1, [
            ("Deadhang",                           "2xmax"),
        ]),
    ]),
    ("Mercredi AM — Jambes A", [
        ("mobility", 0, [
            ("90/90 Hip + Band Shoulder Rotation", "3x45s/côté"),
            ("World's Greatest Stretch",           "3x5/côté"),
        ]),
        ("explosive", 1, [
            ("Box Jump",                           "4x3"),
            ("Broad Jump",                         "3x3"),
        ]),
        ("force", 2, [
            ("Back Squat",                         "4x5-8"),
            ("Romanian Deadlift",                  "4x6-8"),
        ]),
    ]),
    ("Mercredi PM — Jambes A", [
        ("isolation", 0, [
            ("Bulgarian Split Squat",              "3x8-12/côté"),
            ("Leg Press",                          "4x10-15"),
            ("Leg Curl",                           "5x10-15"),
            ("Leg Extension",                      "3x12-15"),
            ("Standing Calf Raise",                "4x15-20"),
        ]),
        ("core", 1, [
            ("Hanging Leg Raise",                  "3x10-12"),
            ("Abs wheel",                          "3x8-10"),
        ]),
    ]),
    ("Jeudi AM — Push B", [
        ("mobility", 0, [
            ("Thoracic Extension + Open Book",     "2x8"),
            ("Wall Slides",                        "2x10"),
        ]),
        ("explosive", 1, [
            ("Medicine Ball Overhead Throw",       "4x5"),
        ]),
        ("force", 2, [
            ("Overhead Press",                     "4x5-8"),
            ("Seated Z Press",                     "3x6-10"),
        ]),
    ]),
    ("Jeudi PM — Push B", [
        ("isolation", 0, [
            ("Cable Lateral Raise",                "4x12-15"),
            ("Dumbbell Lateral Raise",             "3x12-15"),
            ("Rear Delt Cable Fly",                "3x12-15"),
            ("Barbell Upright Row",                "3x10-12"),
            ("Triceps Pushdown",                   "3x10-15"),
        ]),
        ("finisher", 1, [
            ("Neck Extension",                     "2x12-15"),
            ("Neck Curl",                          "2x12-15"),
        ]),
    ]),
    ("Vendredi AM — Pull B", [
        ("mobility", 0, [
            ("World's Greatest Stretch",           "3x5/côté"),
            ("Band Pull-Apart",                    "2x15"),
        ]),
        ("explosive", 1, [
            ("Medicine Ball Slam",                 "4x5"),
        ]),
        ("force", 2, [
            ("Pull-Up",                            "4x5-8"),
            ("T-Bar Row",                          "4x6-10"),
        ]),
    ]),
    ("Vendredi PM — Pull B", [
        ("isolation", 0, [
            ("Lat Pulldown",                       "4x10-12"),
            ("Chest-Supported DB Row",             "3x10-12"),
            ("Rope Hammer Curl",                   "4x10-15"),
            ("Reverse Curl",                       "3x10-15"),
            ("Face Pull",                          "3x15"),
        ]),
        ("finisher", 1, [
            ("Deadhang",                           "2xmax"),
        ]),
    ]),
    ("Dimanche AM — Jambes B", [
        ("mobility", 0, [
            ("90/90 Hip + Band Shoulder Rotation", "3x45s/côté"),
            ("World's Greatest Stretch",           "3x5/côté"),
        ]),
        ("explosive", 1, [
            ("Box Jump",                           "3x3"),
            ("Lateral Bound",                      "3x4/côté"),
        ]),
        ("force", 2, [
            ("Hip Thrust",                         "4x8-12"),
            ("Walking Lunge",                      "3x10-12/côté"),
        ]),
    ]),
    ("Dimanche PM — Jambes B", [
        ("isolation", 0, [
            ("Leg Curl",                           "4x12-15"),
            ("Nordic Hamstring Curl",              "3x6-8"),
            ("Standing Calf Raise",                "4x15-20"),
            ("Barbell Shrug",                      "3x10-12"),
        ]),
        ("core", 1, [
            ("Farmer's Carry",                     "3x40m"),
            ("Cable Woodchopper",                  "3x10-12/côté"),
            ("Pallof Press",                       "3x10-12/côté"),
            ("Hollow Body Crunch",                 "3x30s"),
            ("Cable Crunch",                       "3x12-15"),
        ]),
    ]),
]


def _build_payload() -> dict:
    """Traduit SESSIONS en dict save_full_program.
    STOP code 4 si un nom d'exo est dupliqué dans un même bloc (spec cassée).
    """
    program: dict = {}
    for session_name, blocks in SESSIONS:
        built_blocks = []
        for btype, border, exos in blocks:
            names = [n for n, _ in exos]
            exo_dict = {n: s for n, s in exos}
            if len(exo_dict) != len(exos):
                dup = sorted({n for n in names if names.count(n) > 1})
                print(f"ERROR: session {session_name!r} bloc {btype!r} — exo dupliqué : {dup}")
                sys.exit(4)
            built_blocks.append({
                "type": btype,
                "order": border,
                "exercises": exo_dict,
            })
        program[session_name] = {"blocks": built_blocks}
    return program


def _distinct_exercise_names(payload: dict) -> set[str]:
    names: set[str] = set()
    for sess in payload.values():
        for blk in sess.get("blocks", []):
            names.update((blk.get("exercises") or {}).keys())
    return names


def _preflight(c, payload: dict) -> None:
    """HARD GATE : chaque nom du payload doit exister ET être vivant.
    STOP code 2 sur miss (absent OU soft-deleted).
    Motif : save_full_program (api/db_programs.py:535-547) auto-crée en silence
    une ligne NULL sur miss — corruption catalogue garantie sans ce gate.
    """
    expected = _distinct_exercise_names(payload)
    print(f"\n[PREFLIGHT] {len(expected)} noms d'exos distincts dans le payload")
    resp = (c.table("exercises")
             .select("name")
             .in_("name", list(expected))
             .is_("deleted_at", "null")
             .execute())
    live = {row["name"] for row in (resp.data or [])}
    missing = expected - live
    if missing:
        print(f"  STOP: {len(missing)} nom(s) absent(s) ou soft-deleted :")
        for n in sorted(missing):
            print(f"    - {n!r}")
        sys.exit(2)
    print(f"  OK — {len(live)}/{len(expected)} présents et vivants.")


def _backup_existing(c, dry_run: bool) -> int:
    """STEP 0 : snapshot JSON complet si un programme v4 existe déjà.
    Retour : 0 OK (ou rien à backup), 7 si écriture backup impossible.
    """
    print("\n[STEP 0] Backup programme v4 préexistant (si présent) :")
    r = c.table("programs").select("id,name,created_at").eq("name", PROGRAM_NAME).execute()
    if not r.data:
        print("  aucun programme 'GymProgramme v4' préexistant — rien à backup.")
        return 0
    pid = r.data[0]["id"]
    sess = (c.table("program_sessions")
             .select("id,name,order_index,"
                     "program_blocks(id,type,order_index,hiit_config,"
                     "program_block_exercises(exercise_id,scheme,order_index))")
             .eq("program_id", pid)
             .execute())
    snapshot = {
        "timestamp": datetime.now().isoformat(timespec="seconds"),
        "context":   f"pre-seed {PROGRAM_NAME} — cutover backup",
        "program":   r.data[0],
        "sessions":  sess.data or [],
    }
    if dry_run:
        print(f"  [DRY RUN] programme préexistant id={pid}, {len(sess.data or [])} sessions — snapshot NON écrit.")
        return 0
    try:
        BACKUP_DIR.mkdir(parents=True, exist_ok=True)
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        path = BACKUP_DIR / f"gymprogramme_v4_{ts}.json"
        path.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2, default=str), encoding="utf-8")
    except Exception as e:
        print(f"  ERROR: écriture backup impossible : {e}")
        return 7
    print(f"  SNAPSHOT écrit : {path} ({len(sess.data or [])} sessions sauvegardées)")
    return 0


def _create_or_reuse_program(c) -> str | None:
    r = c.table("programs").select("id").eq("name", PROGRAM_NAME).execute()
    if r.data:
        pid = r.data[0]["id"]
        print(f"\n[STEP 1] REUSE programs id={pid}")
        return pid
    print(f"\n[STEP 1] INSERT programs (name={PROGRAM_NAME!r}) :")
    ins = c.table("programs").insert({"name": PROGRAM_NAME}).execute()
    if not ins.data:
        print("  ERROR: INSERT programs a retourné data=[] — vérifier RLS anon_all.")
        return None
    pid = ins.data[0]["id"]
    print(f"  created id={pid}")
    return pid


def _verify_post_save(c, program_id: str, expected: dict) -> int:
    """Recharge via get_full_program et compare aux comptes attendus."""
    print("\n[STEP 3] Vérif post-save (get_full_program) :")
    got = db_programs.get_full_program(program_id) or {}
    if len(got) != len(expected):
        print(f"  ERROR: sessions rechargées = {len(got)}, attendu {len(expected)}")
        return 6
    ok = True
    for name, sess in expected.items():
        got_sess = got.get(name)
        if not got_sess:
            print(f"  MISS session : {name!r}")
            ok = False
            continue
        exp_blocks = sess["blocks"]
        got_blocks = got_sess.get("blocks", [])
        exp_exos = sum(len(b.get("exercises") or {}) for b in exp_blocks)
        got_exos = sum(len(b.get("exercises") or {}) for b in got_blocks)
        marker = "OK  " if (len(got_blocks) == len(exp_blocks) and got_exos == exp_exos) else "MISS"
        if marker == "MISS":
            ok = False
        print(f"  {marker} {name!r:44s} blocs={len(got_blocks)}/{len(exp_blocks)} exos={got_exos}/{exp_exos}")
    return 0 if ok else 6


def run(dry_run: bool) -> int:
    c = db_core._client
    if c is None:
        print("ERROR: db_core._client is None (OFFLINE ou env manquants).")
        return 1

    payload = _build_payload()  # peut sys.exit(4) sur doublon intra-bloc
    total_blocks = sum(len(s["blocks"]) for s in payload.values())
    total_exos = sum(len(b["exercises"]) for s in payload.values() for b in s["blocks"])
    types_count: dict = {}
    for s in payload.values():
        for b in s["blocks"]:
            types_count[b["type"]] = types_count.get(b["type"], 0) + 1
    print(f"\n[BUILD] {len(payload)} sessions, {total_blocks} blocs, {total_exos} exos")
    print(f"        ventilation par type : {dict(sorted(types_count.items()))}")

    _preflight(c, payload)  # peut sys.exit(2)

    rc = _backup_existing(c, dry_run)
    if rc != 0:
        print("\nSTOP: backup échoué — aucune écriture v4.")
        return rc

    if dry_run:
        print("\n[DRY RUN] Aucune écriture DB. Actions prévues :")
        print(f"  REUSE ou INSERT programs {PROGRAM_NAME!r}")
        print(f"  save_full_program : {len(payload)} sessions, {total_blocks} blocs, {total_exos} exos")
        for name, sess in payload.items():
            n_ex = sum(len(b["exercises"]) for b in sess["blocks"])
            print(f"    {name!r:44s} blocs={len(sess['blocks'])} exos={n_ex}")
        return 0

    program_id = _create_or_reuse_program(c)
    if program_id is None:
        return 3

    print(f"\n[STEP 2] save_full_program ({len(payload)} sessions, {total_blocks} blocs, {total_exos} exos) :")
    ok = db_programs.save_full_program(payload, program_id=program_id)
    if not ok:
        print("  ERROR: save_full_program a retourné False.")
        return 5
    print("  OK — save_full_program retour True.")

    return _verify_post_save(c, program_id, payload)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="Affiche sans écrire (ni DB, ni fichier).")
    args = ap.parse_args()
    sys.exit(run(dry_run=args.dry_run))
