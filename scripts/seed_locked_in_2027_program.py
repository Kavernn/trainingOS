#!/usr/bin/env python3
"""
Seed programme 'Locked In 2027' (2026-08-03).

13 séances (Lun→Dim, order_index 0..12), 63 slots exos, 48 noms distincts,
tous en blocs strength (chantier 3 pour cardio/hiit/protocol dispatch).
Prérequis : seed_locked_in_2027_catalogue.py déjà exécuté (48/48 exos vérifiés).

Idempotent :
    - P0b : programme existant → REUSE son id, save_full_program remplace le contenu.
    - save_full_program : on_conflict(program_id,name) sur sessions ; match
      (session_id,type,order_index) sur blocks ; DELETE+INSERT sur block_exercises.
    - weekly_schedule : upsert on_conflict(day_name,slot) inline.

HARD GATE P0c : 48 exos vérifiés avant écriture. Un manquant = STOP (code 2).
STEP 0 : snapshot weekly_schedule → scripts/backups/<horodaté>.json avant tout write.
    Si écriture impossible → STOP (code 7). Le backup est réversible à la main.

Effet de bord assumé : weekly_schedule est remappé vers Locked In 2027
(7 morning + 6 evening = 13 rangs). Snapshot préalable = filet de sécurité.

Aucune écriture exercise_logs. Aucun log touché.

Run:
    python3 scripts/seed_locked_in_2027_program.py [--dry-run]
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
from blocks import make_strength_block  # noqa: E402


PROGRAM_NAME = "Locked In 2027"
BACKUP_DIR = Path(__file__).parent / "backups"

# ─────────────────────────────────────────────────────────────────────────────
# SPEC — 13 séances (Lun→Dim, order 0..12)
# (session_name, day_name_court, slot, [(exo, scheme), ...])
# ─────────────────────────────────────────────────────────────────────────────
SESSIONS: list[tuple[str, str, str, list[tuple[str, str]]]] = [
    ("Lundi AM — Jambes", "Lun", "morning", [
        ("Back Squat",                     "4x5-8"),
        ("Leg Press",                      "3x10-12"),
        ("Leg Extension",                  "3x12-15"),
        ("Calf Raise",                     "4x8-12"),
        ("Deadhang",                       "2xmax"),
    ]),
    ("Lundi PM — Haut du corps", "Lun", "evening", [
        ("Cable Lateral Raise",            "5x12-15"),
        ("Triceps Pushdown",               "3x10-12"),
        ("Neck Curl",                      "3x12-15"),
        ("Abs wheel",                      "3x8-12"),
        ("Deadhang",                       "1xmax"),
    ]),
    ("Mardi AM — Épaules", "Mar", "morning", [
        ("Overhead Press",                 "4x5-8"),
        ("Incline Barbell Press",          "3x6-10"),
        ("Barbell Upright Row",            "3x10-12"),
        ("Dumbbell Lateral Raise",         "4x12-15"),
        ("Deadhang",                       "2xmax"),
    ]),
    ("Mardi PM — Puissance + bras + pelvien", "Mar", "evening", [
        ("Medicine Ball Rotational Throw", "5x4"),
        ("Rear Delt Cable Fly",            "3x15-20"),
        ("Incline DB Curl",                "4x8-12"),
        ("Bloc plancher pelvien",          "1x5min"),
        ("Deadhang",                       "1xmax"),
    ]),
    ("Mercredi AM — Dos", "Mer", "morning", [
        ("Barbell Row",                    "3x6-10"),
        ("Chest-Supported DB Row",         "3x10-12"),
        ("Seated Cable Row",               "2x10-12"),
        ("Face Pull",                      "3x15-20"),
        ("Deadhang",                       "2xmax"),
    ]),
    ("Mercredi PM — Zone-2 + mobilité + pelvien", "Mer", "evening", [
        ("Zone-2 (vélo/rameur)",           "1x30min"),
        ("Thoracic Extension + Open Book", "2x10"),
        ("Pallof Press",                   "3x12"),
        ("Bloc plancher pelvien",          "1x5min"),
        ("Deadhang",                       "1xmax"),
    ]),
    ("Jeudi AM — Pecs", "Jeu", "morning", [
        ("Bench Press",                    "4x5-8"),
        ("Flat DB Press",                  "3x8-12"),
        ("Cable Fly / Pec Dec",            "3x12-15"),
        ("Triceps Pushdown",               "3x10-12"),
        ("Deadhang",                       "2xmax"),
    ]),
    ("Jeudi PM — Intervalles + bras + core", "Jeu", "evening", [
        ("Intervalles (VO2)",              "8x30s"),
        ("Overhead Triceps Extension",     "3x10-12"),
        ("Rope Hammer Curl",               "3x12-15"),
        ("Hanging Leg Raise",              "3x10-15"),
        ("Deadhang",                       "1xmax"),
    ]),
    ("Vendredi AM — Chaîne postérieure", "Ven", "morning", [
        ("Romanian Deadlift",              "4x6-8"),
        ("Hip Thrust",                     "3x8-12"),
        ("Leg Curl",                       "3x10-12"),
        ("Copenhagen / Side Plank",        "3x30s"),
        ("Deadhang",                       "2xmax"),
    ]),
    ("Vendredi PM — Carry + hanche + pelvien", "Ven", "evening", [
        ("Farmer's Carry",                 "4x40m"),
        ("Cable Pull-Through",             "3x12-15"),
        ("Neck Extension",                 "3x12-15"),
        ("Bloc plancher pelvien",          "1x5min"),
        ("Deadhang",                       "1xmax"),
    ]),
    ("Samedi AM — Récup (optionnel)", "Sam", "morning", [
        ("World's Greatest Stretch",           "2x5"),
        ("90/90 Hip + Band Shoulder Rotation", "2x8"),
        ("Deadhang",                            "2xmax"),
    ]),
    ("Dimanche AM — Largeur dos + bras", "Dim", "morning", [
        ("Pull-Up",                        "4x6-10"),
        ("Lat Pulldown",                   "3x10-12"),
        ("T-Bar Row",                      "3x8-10"),
        ("Barbell Curl",                   "4x8-10"),
        ("Deadhang",                       "2xmax"),
    ]),
    ("Dimanche PM — Puissance + bras + core", "Dim", "evening", [
        ("Box Jump",                       "5x3"),
        ("Cable Curl",                     "3x10-12"),
        ("Cable Crunch",                   "3x12-15"),
        ("Cable Woodchopper",              "3x12"),
        ("Deadhang",                       "1xmax"),
    ]),
]


def _distinct_exercise_names() -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for _, _, _, exos in SESSIONS:
        for n, _ in exos:
            if n not in seen:
                seen.add(n)
                out.append(n)
    return out


def preflight(c) -> tuple[dict[str, str], str | None]:
    """Retourne (name_to_id, existing_program_id_or_None). Raise sur P0c fail."""
    print("\n[P0b] Programme existant ?")
    p = c.table("programs").select("id").eq("name", PROGRAM_NAME).execute()
    existing_id = p.data[0]["id"] if p.data else None
    if existing_id:
        print(f"  '{PROGRAM_NAME}' existe déjà (id={existing_id}) — re-run idempotent.")
    else:
        print(f"  '{PROGRAM_NAME}' absent — sera créé.")

    names = _distinct_exercise_names()
    print(f"\n[P0c] HARD GATE : {len(names)} noms distincts à vérifier.")
    resp = c.table("exercises").select("id,name").in_("name", names).is_("deleted_at", "null").execute()
    found = {row["name"]: row["id"] for row in (resp.data or [])}
    missing = [n for n in names if n not in found]
    if missing:
        print(f"  STOP ({len(missing)} manquant(s), catalogue à compléter) :")
        for n in missing:
            print(f"    MISSING {n!r}")
        raise RuntimeError(f"P0c failed: {len(missing)} exercise(s) missing")
    print(f"  OK — {len(found)}/{len(names)} exos trouvés.")

    print("\n[P0d] weekly_schedule.day_name live :")
    ws = c.table("weekly_schedule").select("day_name,slot").execute()
    days = sorted({row["day_name"] for row in (ws.data or [])})
    expected = {"Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"}
    print(f"  live = {days}")
    if not expected.issubset(set(days)):
        missing_days = expected - set(days)
        print(f"  WARNING: jours attendus absents en live : {missing_days}")
        print(f"           upsert on_conflict(day_name,slot) créera ces rangs.")

    return found, existing_id


def _fetch_weekly_snapshot(c) -> list[dict]:
    """
    SELECT weekly_schedule + JOIN program_sessions(name) + programs(name) via PostgREST
    embed. Retourne liste lisible humain :
      [{day_name, slot, session_id, session_name|None, program_name|None}, ...]
    Rangs sans session_id : session_name/program_name = None (jour vide).
    """
    resp = c.table("weekly_schedule").select(
        "day_name,slot,session_id,program_sessions(name,programs(name))"
    ).execute()
    rows: list[dict] = []
    for r in (resp.data or []):
        sess = r.get("program_sessions") or {}
        prog = (sess.get("programs") or {}) if sess else {}
        rows.append({
            "day_name":     r.get("day_name"),
            "slot":         r.get("slot"),
            "session_id":   r.get("session_id"),
            "session_name": sess.get("name") if sess else None,
            "program_name": prog.get("name") if prog else None,
        })
    day_order = {"Lun": 0, "Mar": 1, "Mer": 2, "Jeu": 3, "Ven": 4, "Sam": 5, "Dim": 6}
    slot_order = {"morning": 0, "evening": 1}
    rows.sort(key=lambda r: (day_order.get(r["day_name"], 99), slot_order.get(r["slot"], 99)))
    return rows


def snapshot_step(c, dry_run: bool) -> int:
    """
    STEP 0 — snapshot weekly_schedule AVANT tout write.
    Dry-run : lit et affiche, n'écrit rien.
    Réel    : écrit scripts/backups/weekly_schedule_backup_<YYYYMMDD_HHMMSS>.json
              → STOP code 7 si écriture impossible.
    """
    print("\n[STEP 0] Snapshot weekly_schedule (avant remap) :")
    try:
        rows = _fetch_weekly_snapshot(c)
    except Exception as e:
        print(f"  ERROR: SELECT weekly_schedule a échoué : {e}")
        return 7
    print(f"  {len(rows)} rangs lus. Contenu actuel :")
    for r in rows:
        sn = r["session_name"] or "<vide>"
        pn = r["program_name"] or "<vide>"
        print(f"    {r['day_name']!r} {r['slot']!r:9s} → {sn!r:40s} (prog={pn!r})")

    if dry_run:
        print(f"  [DRY RUN] Aucune écriture fichier. Chemin cible (réel) :")
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        preview = BACKUP_DIR / f"weekly_schedule_backup_{ts}.json"
        print(f"    {preview}")
        return 0

    try:
        BACKUP_DIR.mkdir(parents=True, exist_ok=True)
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        path = BACKUP_DIR / f"weekly_schedule_backup_{ts}.json"
        payload = {
            "timestamp":   datetime.now().isoformat(timespec="seconds"),
            "context":     f"pre-seed {PROGRAM_NAME} — cutover backup",
            "row_count":   len(rows),
            "rows":        rows,
        }
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    except Exception as e:
        print(f"  ERROR: écriture backup impossible : {e}")
        return 7
    print(f"  SNAPSHOT écrit : {path} ({len(rows)} rangs sauvegardés)")
    return 0


def run(dry_run: bool) -> int:
    c = db_core._client
    if c is None:
        print("ERROR: db_core._client is None (OFFLINE ou env manquants).")
        return 1

    try:
        _name_to_id, existing_program_id = preflight(c)
    except RuntimeError as e:
        print(f"\nSTOP: {e}")
        return 2

    rc = snapshot_step(c, dry_run)
    if rc != 0:
        print("\nSTOP: snapshot échoué — aucun remap effectué.")
        return rc

    if dry_run:
        print("\n[DRY RUN] Aucune écriture DB. Actions prévues :")
        if existing_program_id:
            print(f"  REUSE programs id={existing_program_id}")
        else:
            print(f"  INSERT programs (name={PROGRAM_NAME!r})")
        total_pbe = sum(len(exos) for _, _, _, exos in SESSIONS)
        print(f"  save_full_program : 13 sessions, {total_pbe} program_block_exercises")
        for i, (name, day, slot, exos) in enumerate(SESSIONS):
            print(f"    [{i:2d}] {name!r:52s} day={day!r} slot={slot!r} exos={len(exos)}")
        print(f"  UPSERT weekly_schedule × {len(SESSIONS)} (7 morning + 6 evening)")
        return 0

    if existing_program_id:
        program_id = existing_program_id
        print(f"\n[STEP 1] REUSE program id={program_id}")
    else:
        print("\n[STEP 1] INSERT programs :")
        ins = c.table("programs").insert({"name": PROGRAM_NAME}).execute()
        if not ins.data:
            print(f"  ERROR: INSERT programs a retourné data=[] — vérifier RLS anon_all.")
            return 3
        program_id = ins.data[0]["id"]
        print(f"  created id={program_id}")

    total_exos = sum(len(exos) for _, _, _, exos in SESSIONS)
    print(f"\n[STEP 2] save_full_program (13 sessions, {total_exos} exos, 13 blocs strength) :")
    program: dict = {}
    for session_name, _, _, exos in SESSIONS:
        exo_dict = {n: s for n, s in exos}
        if len(exo_dict) != len(exos):
            print(f"  ERROR: séance {session_name!r} contient un nom d'exo dupliqué — spec cassée.")
            return 4
        program[session_name] = {"blocks": [make_strength_block(exo_dict, order=0)]}
    ok = db_programs.save_full_program(program, program_id)
    if not ok:
        print(f"  ERROR: save_full_program a retourné False.")
        return 5
    print(f"  OK — 13 sessions upsertées.")

    print(f"\n[STEP 3] UPSERT weekly_schedule (13 rangs) :")
    sess_resp = (c.table("program_sessions")
                 .select("id,name")
                 .eq("program_id", program_id)
                 .execute())
    sess_id_by_name = {row["name"]: row["id"] for row in (sess_resp.data or [])}
    for session_name, day, slot, _ in SESSIONS:
        sid = sess_id_by_name.get(session_name)
        if not sid:
            print(f"  ERROR: session_id introuvable pour {session_name!r} — save_full_program incohérent.")
            return 6
        c.table("weekly_schedule").upsert(
            {"day_name": day, "slot": slot, "session_id": sid},
            on_conflict="day_name,slot",
        ).execute()
        print(f"  UPSERT day={day!r} slot={slot!r} → {session_name!r}")

    print("\n[preuves post-seed] :")
    q = (c.table("program_sessions")
         .select("id,name,order_index", count="exact")
         .eq("program_id", program_id)
         .execute())
    print(f"  program_sessions count = {q.count} (attendu 13)")
    for row in sorted(q.data or [], key=lambda r: r["order_index"]):
        blocks = (c.table("program_blocks")
                  .select("id").eq("session_id", row["id"]).execute()).data or []
        pbe_count = 0
        for b in blocks:
            r2 = (c.table("program_block_exercises")
                  .select("id", count="exact").eq("block_id", b["id"]).execute())
            pbe_count += (r2.count or 0)
        print(f"    [{row['order_index']:2d}] {row['name']!r:52s} blocks={len(blocks)} exos={pbe_count}")

    ws_final = c.table("weekly_schedule").select("day_name,slot,session_id").execute()
    ws_linked = [r for r in (ws_final.data or []) if r.get("session_id")]
    print(f"  weekly_schedule rangs avec session_id = {len(ws_linked)} (attendu ≥13)")

    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="Affiche sans écrire (ni DB, ni fichier).")
    args = ap.parse_args()
    sys.exit(run(dry_run=args.dry_run))
