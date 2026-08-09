#!/usr/bin/env python3
"""
Bascule GymProgramme v4 = actif (2026-08-09).

Ce script est le SEUL du chantier v4 qui modifie l'état vivant :
    - réécrit weekly_schedule (14 lignes : 12 sessions v4 + Sam morning/evening NULL)
    - flippe user_profile.active_program_id vers v4

Locked In 2027 reste intact en base (programme, sessions, blocs, exos préservés) ;
seul le planning est repointé.

Contrat vérifié en diagnostic :
    - weekly_schedule n'a PAS de colonne program_id ; get_relational_week_schedule
      (api/db_programs.py:605-641) lit SANS filtre active_program_id → la bascule
      DOIT réécrire weekly_schedule dans le même run, sinon désync garantie.
    - session_id NULLABLE, lu comme "Repos" (L626-628). Samedi → NULL, pas DELETE
      (le bootstrap schema.sql:129-131 réinsère la ligne morning).
    - Aucun trigger, aucune vue matérialisée, aucun cache serveur.

Idempotent :
    - upsert weekly_schedule on_conflict(day_name,slot)
    - UPDATE user_profile WHERE id=1 (single-row, unicité par construction)

STEP 0 : backup JSON avant toute écriture
         (scripts/backups/activate_v4_<horodaté>.json).
STEP 1 : preflight — v4 doit exister et TOUS les session_id doivent lui appartenir.
STEP 2 : remap weekly_schedule (14 upserts).
STEP 3 : flip active_program_id.
STEP 4 : vérif in-script (lecture, PASS/FAIL, pas de rollback auto).

Codes de sortie :
    0 succès
    1 client None (OFFLINE / env manquants)
    2 preflight v4 absent
    3 preflight session_id étrangère à v4
    5 échec upsert weekly_schedule ou flip
    6 vérif post-bascule KO
    7 backup fail
    8 rollback fail

Run :
    python3 scripts/activate_gymprogramme_v4.py --dry-run
    python3 scripts/activate_gymprogramme_v4.py
    python3 scripts/activate_gymprogramme_v4.py --rollback scripts/backups/activate_v4_<ts>.json
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


# ─────────────────────────────────────────────────────────────────────────────
# CONSTANTES — ids littéraux (vérifiés en diagnostic diff 5A + preflight ci-dessous)
# ─────────────────────────────────────────────────────────────────────────────
V4_PROGRAM_ID   = "7ddfa7a6-297b-485f-9208-fccc9b921cce"
PREV_PROGRAM_ID = "8dfb0436-19b9-40a4-8f81-ad50e0b6e1cf"  # Locked In 2027

# (day_name, slot, session_id | None)  — 14 opérations
REMAP: list[tuple[str, str, str | None]] = [
    ("Lun", "morning", "ac12f342-4459-48c8-837d-a91b48d72c85"),
    ("Lun", "evening", "d3481d16-6941-43a3-908e-3a0ddd3e8043"),
    ("Mar", "morning", "c7ecc4f2-28fe-4bfb-aef7-f0f39de08999"),
    ("Mar", "evening", "eb6108af-941c-419e-bf89-e7644ad301c4"),
    ("Mer", "morning", "d9668fbd-930b-4259-be77-1fd866555676"),
    ("Mer", "evening", "dbd8106c-d878-45d5-9d03-e43811e64a73"),
    ("Jeu", "morning", "7b5130df-c773-4829-bc45-0c5d13ce1360"),
    ("Jeu", "evening", "a962d72e-2238-48dd-8b1e-a74fcbf4ccbf"),
    ("Ven", "morning", "310f4527-015b-47e5-a78c-153bc31e7af8"),
    ("Ven", "evening", "d8ab1b16-1f8c-4005-bbc0-f9ca68c7b7ec"),
    ("Sam", "morning", None),
    ("Sam", "evening", None),
    ("Dim", "morning", "7d4b3b2a-3c5e-4146-9962-6962b06c1cfd"),
    ("Dim", "evening", "8ad86f14-604d-454c-8ba3-0f597460ef39"),
]

BACKUP_DIR = Path(__file__).parent / "backups"


def _fetch_active_program_id(c) -> str | None:
    r = c.table("user_profile").select("active_program_id").eq("id", 1).single().execute()
    if not r.data:
        return None
    v = r.data.get("active_program_id")
    return str(v) if v else None


def _fetch_weekly_schedule(c) -> list[dict]:
    r = c.table("weekly_schedule").select("day_name,slot,session_id").execute()
    return r.data or []


# ─────────────────────────────────────────────────────────────────────────────
# STEP 0 — BACKUP
# ─────────────────────────────────────────────────────────────────────────────
def _backup(c, dry_run: bool) -> tuple[int, Path | None]:
    print("\n[STEP 0] Backup pré-bascule :")
    try:
        active_now = _fetch_active_program_id(c)
        ws_rows = _fetch_weekly_schedule(c)
    except Exception as e:
        print(f"  ERROR: SELECT backup a échoué : {e}")
        return 7, None
    snapshot = {
        "timestamp":          datetime.now().isoformat(timespec="seconds"),
        "context":            "pre-activate GymProgramme v4 — bascule cutover",
        "active_program_id":  active_now,
        "weekly_schedule":    ws_rows,
    }
    print(f"  active_program_id actuel = {active_now!r}")
    print(f"  weekly_schedule : {len(ws_rows)} lignes lues")
    if dry_run:
        print("  [DRY RUN] snapshot NON écrit.")
        return 0, None
    try:
        BACKUP_DIR.mkdir(parents=True, exist_ok=True)
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        path = BACKUP_DIR / f"activate_v4_{ts}.json"
        path.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2, default=str), encoding="utf-8")
    except Exception as e:
        print(f"  ERROR: écriture backup impossible : {e}")
        return 7, None
    print(f"  SNAPSHOT écrit : {path}")
    return 0, path


# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — PREFLIGHT
# ─────────────────────────────────────────────────────────────────────────────
def _preflight(c) -> int:
    print("\n[STEP 1] Preflight :")
    # a) v4 existe
    r = c.table("programs").select("id,name").eq("id", V4_PROGRAM_ID).execute()
    if not r.data:
        print(f"  STOP: programs.id={V4_PROGRAM_ID} introuvable.")
        return 2
    print(f"  (a) programs.id={V4_PROGRAM_ID} OK ({r.data[0].get('name')!r})")

    # b) les 12 session_id non-NULL appartiennent tous à v4
    expected_sids = [sid for _, _, sid in REMAP if sid is not None]
    r2 = (c.table("program_sessions")
          .select("id,name,program_id")
          .in_("id", expected_sids)
          .eq("program_id", V4_PROGRAM_ID)
          .execute())
    matched = {str(row["id"]) for row in (r2.data or [])}
    missing = set(expected_sids) - matched
    if missing:
        print(f"  STOP: {len(missing)}/{len(expected_sids)} session_id n'appartiennent PAS à v4 :")
        for sid in sorted(missing):
            # info diag : où est cet id, s'il existe ?
            r3 = c.table("program_sessions").select("name,program_id").eq("id", sid).execute()
            if r3.data:
                row = r3.data[0]
                print(f"    - {sid} → name={row.get('name')!r} program_id={row.get('program_id')!r}")
            else:
                print(f"    - {sid} → INTROUVABLE en base")
        return 3
    print(f"  (b) {len(matched)}/{len(expected_sids)} sessions vérifiées, toutes attachées à v4 OK")
    print("  preflight OK : v4 présent, 12 sessions vérifiées appartenant à v4")
    return 0


# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — REMAP
# ─────────────────────────────────────────────────────────────────────────────
def _remap(c) -> int:
    print(f"\n[STEP 2] Remap weekly_schedule ({len(REMAP)} lignes) :")
    for day, slot, sid in REMAP:
        try:
            c.table("weekly_schedule").upsert(
                {"day_name": day, "slot": slot, "session_id": sid},
                on_conflict="day_name,slot",
            ).execute()
        except Exception as e:
            print(f"  ERROR: upsert ({day},{slot}) → {e}")
            return 5
        marker = "REPOS" if sid is None else sid[:8]
        print(f"  UPSERT {day} {slot:8s} → {marker}")
    return 0


# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — FLIP
# ─────────────────────────────────────────────────────────────────────────────
def _flip(pid: str) -> int:
    print(f"\n[STEP 3] Flip user_profile.active_program_id → {pid}")
    ok = db_programs.set_active_program_id(pid)
    if not ok:
        print("  ERROR: set_active_program_id a retourné False.")
        return 5
    print("  OK")
    return 0


# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 — VÉRIF
# ─────────────────────────────────────────────────────────────────────────────
def _verify(c) -> int:
    print("\n[STEP 4] Vérif post-bascule :")
    ok = True

    active = _fetch_active_program_id(c)
    passed = (active == V4_PROGRAM_ID)
    print(f"  {'PASS' if passed else 'FAIL'} active_program_id = {active!r} (attendu {V4_PROGRAM_ID!r})")
    if not passed:
        ok = False

    r = (c.table("weekly_schedule")
         .select("day_name,slot,session_id,program_sessions(name,programs(name))")
         .execute())
    rows = r.data or []
    day_order = {"Lun": 0, "Mar": 1, "Mer": 2, "Jeu": 3, "Ven": 4, "Sam": 5, "Dim": 6}
    rows.sort(key=lambda x: (day_order.get(x.get("day_name"), 99),
                             0 if x.get("slot") == "morning" else 1))

    n_v4 = n_repos = n_other = 0
    print(f"  {'day':4s} {'slot':8s}  {'programme':20s} session")
    for row in rows:
        sess = row.get("program_sessions") or {}
        prog = (sess.get("programs") or {}) if sess else {}
        prog_name = prog.get("name") if prog else None
        sess_name = sess.get("name") if sess else None
        if row.get("session_id") is None:
            n_repos += 1
            print(f"  {row['day_name']:4s} {row['slot']:8s}  {'—REPOS—':20s} —")
        elif prog_name == "GymProgramme v4":
            n_v4 += 1
            print(f"  {row['day_name']:4s} {row['slot']:8s}  {prog_name:20s} {sess_name}")
        else:
            n_other += 1
            print(f"  {row['day_name']:4s} {row['slot']:8s}  {str(prog_name):20s} {sess_name}   ← INATTENDU")

    passed = (n_v4 == 12 and n_repos == 2 and n_other == 0)
    print(f"  {'PASS' if passed else 'FAIL'} planning : v4={n_v4}/12  repos={n_repos}/2  autres={n_other}/0")
    if not passed:
        ok = False
    return 0 if ok else 6


# ─────────────────────────────────────────────────────────────────────────────
# RUN
# ─────────────────────────────────────────────────────────────────────────────
def run(dry_run: bool) -> int:
    c = db_core._client
    if c is None:
        print("ERROR: db_core._client is None (OFFLINE ou env manquants).")
        return 1

    rc, _ = _backup(c, dry_run)
    if rc != 0:
        print("\nSTOP: backup échoué — aucune bascule.")
        return rc

    rc = _preflight(c)
    if rc != 0:
        return rc

    if dry_run:
        print("\n[DRY RUN] Actions prévues :")
        print(f"  {len(REMAP)} upserts weekly_schedule (12 → v4, 2 → NULL)")
        print(f"  UPDATE user_profile.active_program_id = {V4_PROGRAM_ID}")
        print("  (aucune écriture effectuée)")
        return 0

    rc = _remap(c)
    if rc != 0:
        print("\nSTOP: remap échoué — active_program_id NON flippé. Rollback disponible.")
        return rc

    rc = _flip(V4_PROGRAM_ID)
    if rc != 0:
        print("\nSTOP: flip échoué — weekly_schedule DÉJÀ REMAPPÉ. Rollback recommandé.")
        return rc

    return _verify(c)


# ─────────────────────────────────────────────────────────────────────────────
# ROLLBACK
# ─────────────────────────────────────────────────────────────────────────────
def rollback(backup_path: str) -> int:
    c = db_core._client
    if c is None:
        print("ERROR: db_core._client is None (OFFLINE ou env manquants).")
        return 1

    path = Path(backup_path)
    if not path.exists():
        print(f"ERROR: backup introuvable : {path}")
        return 8
    try:
        snap = json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"ERROR: lecture backup a échoué : {e}")
        return 8

    ws_rows = snap.get("weekly_schedule") or []
    prev_pid = snap.get("active_program_id")
    print(f"\n[ROLLBACK] depuis {path}")
    print(f"  weekly_schedule : {len(ws_rows)} lignes à restaurer")
    print(f"  active_program_id à restaurer : {prev_pid!r}")

    for row in ws_rows:
        day = row.get("day_name")
        slot = row.get("slot")
        sid = row.get("session_id")
        try:
            c.table("weekly_schedule").upsert(
                {"day_name": day, "slot": slot, "session_id": sid},
                on_conflict="day_name,slot",
            ).execute()
        except Exception as e:
            print(f"  ERROR: upsert ({day},{slot}) : {e}")
            return 8
        marker = "REPOS" if sid is None else str(sid)[:8]
        print(f"  RESTORE {day} {slot:8s} → {marker}")

    if prev_pid is not None:
        ok = db_programs.set_active_program_id(prev_pid)
        if not ok:
            print("  ERROR: set_active_program_id (restauration) a retourné False.")
            return 8
        print(f"  RESTORE active_program_id = {prev_pid}")
    else:
        print("  SKIP active_program_id (backup avait la valeur None)")

    print(f"\nrollback appliqué depuis {path}")
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true",
                    help="Imprime le plan + preflight, aucune écriture.")
    ap.add_argument("--rollback", metavar="BACKUP_JSON", default=None,
                    help="Restaure depuis un snapshot JSON produit par STEP 0.")
    args = ap.parse_args()

    if args.rollback:
        sys.exit(rollback(args.rollback))
    sys.exit(run(dry_run=args.dry_run))
