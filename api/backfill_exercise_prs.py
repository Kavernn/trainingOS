"""Backfill one-shot : alimente exercise_prs depuis tout l'historique exercise_logs.

Usage (depuis le dossier api/) :
    python backfill_exercise_prs.py

- Lecture pure sur exercise_logs — jamais modifié.
- Idempotent : peut être relancé sans risque (ON CONFLICT DO UPDATE).
- Doit être relancé UNE FOIS après le déploiement du Diff 2 (write path) pour
  couvrir les logs créés entre le backfill initial et l'activation du write path.
"""
from __future__ import annotations
import sys
import os
from pathlib import Path

# Charge .env.local (credentials Supabase) avant d'importer db
_root = Path(__file__).parent.parent
for _env_file in [".env", ".env.local"]:
    _path = _root / _env_file
    if _path.exists():
        try:
            from dotenv import load_dotenv
            load_dotenv(_path, override=True)
        except ImportError:
            # dotenv absent — parse manuel minimaliste
            for _line in _path.read_text().splitlines():
                _line = _line.strip()
                if _line and not _line.startswith("#") and "=" in _line:
                    _k, _, _v = _line.partition("=")
                    os.environ.setdefault(_k.strip(), _v.strip().strip('"').strip("'"))

# Permet d'importer les modules du backend depuis ce script standalone
sys.path.insert(0, os.path.dirname(__file__))

import db
from progression import estimate_1rm


def _avg_reps_int(reps_str: str) -> int:
    try:
        parts = [int(x) for x in str(reps_str).replace(";", ",").split(",") if x.strip().isdigit()]
        return round(sum(parts) / len(parts)) if parts else 1
    except Exception:
        return 1


def run_backfill() -> None:
    print("=== Backfill exercise_prs ===")

    history = db.get_all_exercise_history(full_history=True)
    if not history:
        print("Aucun historique trouvé. Abandon.")
        return

    print(f"Exercices dans l'historique : {len(history)}")
    ok_count  = 0
    skip_count = 0

    for exercise_name, entries in history.items():
        if not entries:
            continue

        best_e1rm    = 0.0
        best_weight  = 0.0
        best_reps_str = "1"
        best_date    = ""

        for entry in entries:
            w     = float(entry.get("weight") or 0)
            r_str = str(entry.get("reps") or "0")
            d     = str(entry.get("date") or "")
            if not w or not d:
                continue
            e1rm = estimate_1rm(w, r_str) or 0.0
            if e1rm > best_e1rm:
                best_e1rm     = e1rm
                best_weight   = w
                best_reps_str = r_str
                best_date     = d

        if best_e1rm <= 0:
            skip_count += 1
            continue

        # baseline_count = nombre de sessions distinctes (dates uniques comme proxy)
        # La valeur exacte (DISTINCT session_id) sera recalculée proprement au
        # prochain upsert_exercise_pr ou recompute_exercise_pr. Ici on utilise
        # COUNT de dates uniques comme approximation pour le backfill initial.
        dates = set(str(e.get("date") or "")[:10] for e in entries if e.get("date"))
        baseline = len(dates)

        success = db.upsert_exercise_pr(
            exercise_name=exercise_name,
            e1rm_lbs=round(best_e1rm, 2),
            weight_lbs=round(best_weight, 2),
            reps_str=best_reps_str,
            date=best_date,
        )
        # upsert_exercise_pr recalcule baseline_count via session_id — correct.
        # (Les dates uniques ci-dessus ne servent qu'à l'affichage du rapport.)
        if success:
            ok_count += 1
            print(f"  ✓ {exercise_name:<35} PR={best_e1rm:.1f} lbs e1RM  "
                  f"({best_weight:.1f}×{best_reps_str})  {best_date}  "
                  f"sessions≈{baseline}")
        else:
            skip_count += 1
            print(f"  ✗ {exercise_name} — échec upsert (exercise_id introuvable ?)")

    print(f"\nRésultat : {ok_count} PRs insérés/mis à jour, {skip_count} ignorés.")
    print("Backfill terminé. Valide les PRs contre tes records connus avant le Diff 2.")


if __name__ == "__main__":
    run_backfill()
