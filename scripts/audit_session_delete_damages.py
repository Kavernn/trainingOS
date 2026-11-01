"""Audit READ-ONLY : dégâts potentiels de l'ancien api_session_delete.

Jusqu'au commit "backend-A fix session_delete isolation", TOUTE valeur
session_type ≠ "bonus" (y compris "evening", "junk", etc.) tombait dans le
branch `else` et supprimait la séance MORNING. Si un appelant iOS envoyait
"evening" ou autre (ex: HistoriqueView.deleteMuscu avant la migration),
la morning du même jour disparaissait silencieusement.

Ce script liste les dates suspectes SANS rien modifier :

1. Dates avec evening session MAIS sans morning session, alors que le
   programme attendait un AM ce jour-là (= candidats à écrasement AM).
2. Logs exercise_logs orphelins (session_id référence une session absente).

Lecture seule, aucune écriture. Lance :
    .venv/bin/python scripts/audit_session_delete_damages.py
Nécessite SUPABASE_URL + SUPABASE_SERVICE_KEY dans l'env (ou .env).
"""
from __future__ import annotations

import os
import sys
from collections import defaultdict
from datetime import date

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

# Charge .env si présent
_env = os.path.join(os.path.dirname(__file__), "..", ".env")
if os.path.isfile(_env):
    with open(_env) as f:
        for line in f:
            line = line.strip()
            if "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))

import db_core  # noqa: E402

if db_core._client is None or db_core.MODE == "OFFLINE":
    print("❌ Supabase non configuré (SUPABASE_URL/SUPABASE_SERVICE_KEY manquants).")
    sys.exit(1)


def _print_header(title: str) -> None:
    print()
    print("=" * 72)
    print(f"  {title}")
    print("=" * 72)


def fetch_all_sessions() -> list[dict]:
    """workout_sessions complets (date + session_type + id)."""
    resp = (
        db_core._client.table("workout_sessions")
        .select("id,date,session_type")
        .execute()
    )
    return resp.data or []


def fetch_morning_schedule_days() -> set[str]:
    """Jours de la semaine (0..6 lundi..dimanche) où un AM est planifié
    pour le programme actif. On le projette ensuite sur chaque date."""
    try:
        resp = (
            db_core._client.table("programs")
            .select("id,is_active,relational_schedule_morning")
            .eq("is_active", True)
            .limit(1)
            .execute()
        )
        if not resp.data: return set()
        sched = resp.data[0].get("relational_schedule_morning") or {}
        # sched = {"lundi": {...}, "mardi": {...}, ...}  — on prend les clés
        # où la valeur est un dict non vide (= séance planifiée).
        days_fr = {"lundi": 0, "mardi": 1, "mercredi": 2, "jeudi": 3,
                   "vendredi": 4, "samedi": 5, "dimanche": 6}
        return {days_fr[k] for k in sched if sched.get(k)}
    except Exception as e:
        print(f"  ⚠️  schedule introuvable ({e}) — on considère tous les jours comme AM-plan.")
        return {0, 1, 2, 3, 4, 5, 6}


def fetch_orphan_exercise_logs() -> int:
    """Count exercise_logs avec session_id non référencé dans workout_sessions."""
    # Récup tous les session_id des logs et des sessions, diff en Python
    # (évite une requête SQL "NOT IN" qui timeout sur grosses tables).
    logs_resp = (
        db_core._client.table("exercise_logs")
        .select("session_id")
        .execute()
    )
    sess_resp = (
        db_core._client.table("workout_sessions")
        .select("id")
        .execute()
    )
    log_sids = {r.get("session_id") for r in (logs_resp.data or []) if r.get("session_id")}
    sess_ids = {r.get("id") for r in (sess_resp.data or [])}
    orphans = log_sids - sess_ids
    return len(orphans)


def main() -> int:
    _print_header("1. Candidats écrasement AM : evening sans morning")

    sessions = fetch_all_sessions()
    by_date: dict[str, dict[str, list[str]]] = defaultdict(lambda: defaultdict(list))
    for s in sessions:
        d = s.get("date")
        st = s.get("session_type", "morning")
        sid = s.get("id", "?")
        if d:
            by_date[d][st].append(sid)

    am_days = fetch_morning_schedule_days()
    print(f"  Programme actif : AM planifié sur jours {sorted(am_days)} (lundi=0)")
    print()

    suspects = []
    for d in sorted(by_date):
        types = by_date[d]
        if "morning" in types: continue
        if "evening" not in types: continue
        try:
            weekday = date.fromisoformat(d).weekday()
        except ValueError:
            weekday = None
        expected_am = (weekday in am_days) if weekday is not None else None
        if expected_am is True or expected_am is None:
            suspects.append((d, weekday, list(types.keys())))

    if not suspects:
        print("  ✅ Aucune date suspecte (evening sans morning sur jour AM planifié).")
    else:
        print(f"  ⚠️  {len(suspects)} date(s) suspecte(s) — AM attendue, trouvé evening seul :")
        for d, wd, types in suspects:
            wd_str = ["lun","mar","mer","jeu","ven","sam","dim"][wd] if wd is not None else "?"
            print(f"     {d}  ({wd_str})  types présents: {types}")

    _print_header("2. Exercise logs orphelins (session_id → session inexistante)")

    orphan_count = fetch_orphan_exercise_logs()
    if orphan_count == 0:
        print("  ✅ Aucun log orphelin.")
    else:
        print(f"  ⚠️  {orphan_count} session_id(s) distincts référencés par logs sans session associée.")
        print("     → traces d'une suppression de session sans cleanup des logs,")
        print("       OU d'une création de log avant la session (improbable).")

    _print_header("Résumé")
    print(f"  Dates suspectes : {len(suspects)}")
    print(f"  Session_ids orphelins : {orphan_count}")
    print()
    print("Ce script n'a RIEN modifié. Si des suspects apparaissent, les")
    print("inspecter manuellement avant toute restauration.")
    return 0 if not suspects and orphan_count == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
