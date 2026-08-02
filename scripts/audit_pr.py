"""Audit PR : trouve la row coupable derrière un 1RM aberrant dans le hero Stats.

Compare :
  1) Ce que /api/pr-tracker (backend propre) considère comme PR récent
  2) Ce que le calcul iOS naïf sortirait (top 10 1RM depuis stats_data.weights)
  3) Détail brut de Standing Calf Raise (weight/reps/1RM/sets par entry)

Usage : python3 scripts/audit_pr.py
Lit TRAININGOS_API_KEY depuis .env.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

DEFAULT_API_BASE = "https://training-os-rho.vercel.app"
TARGET_EXO       = "Standing Calf Raise"


def load_env_key(env_path: str) -> str | None:
    if not os.path.isfile(env_path):
        return None
    with open(env_path) as f:
        for line in f:
            line = line.strip()
            if line.startswith("TRAININGOS_API_KEY="):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    return None


def _fetch(url: str, token: str) -> dict:
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def epley_or_brzycki(w: float, r: int) -> float:
    """Réplique estimate_1rm côté serveur (progression.py)."""
    if w <= 0 or r <= 0 or r > 20:
        return 0.0
    if r <= 10:
        return w * (1 + r / 30.0)  # Epley
    return w * 36.0 / (37.0 - r)   # Brzycki


def main() -> int:
    env_path = os.path.join(os.path.dirname(__file__), "..", ".env")
    token = os.environ.get("TRAININGOS_API_KEY") or load_env_key(env_path)
    if not token:
        print("ERROR: TRAININGOS_API_KEY absent (env ou .env).")
        return 1

    # --- (1) Ce que le backend considère comme PR récent
    print("── /api/pr-tracker (backend, filtré baseline_count ≥ 2, récence 30j) ──")
    try:
        pr = _fetch(f"{DEFAULT_API_BASE}/api/pr-tracker", token)
        prs = pr.get("recent_prs") or []
        if not prs:
            print(f"  Aucun PR récent. total_prs={pr.get('total_prs')}, "
                  f"exercises_tracked={pr.get('exercises_tracked')}")
        else:
            for p in prs:
                print(f"  {p.get('date')}  {p.get('name'):<30}  est_1rm={p.get('est_1rm')} lbs  "
                      f"(prev best {p.get('prev_best')})")
    except urllib.error.HTTPError as e:
        print(f"  ERROR HTTP {e.code}: {e.read().decode('utf-8', 'replace')[:200]}")
    except Exception as e:
        print(f"  ERROR: {e}")
    print()

    # --- (2) Top 10 1RM que iOS voit (naïf, mimique StatsView.swift:559-566)
    print("── Top 10 1RM (calcul iOS naïf : max 1rm par exo, tri DESC) ──")
    try:
        stats = _fetch(f"{DEFAULT_API_BASE}/api/stats_data", token)
        weights = stats.get("weights") or {}
        tops = []
        for name, data in weights.items():
            hist = (data or {}).get("history") or []
            best = 0.0
            best_row = None
            for e in hist:
                orm = e.get("1rm") or 0
                if orm > best:
                    best = orm
                    best_row = e
            if best > 0 and best_row:
                tops.append((name, best, best_row))
        tops.sort(key=lambda x: x[1], reverse=True)
        for name, best, row in tops[:10]:
            print(f"  {best:>7.1f} lbs  {name:<30}  "
                  f"(row: date={row.get('date')} w={row.get('weight')} r={row.get('reps')})")
    except Exception as e:
        print(f"  ERROR: {e}")
    print()

    # --- (3) Détail brut de la cible
    print(f"── History brute — {TARGET_EXO} ──")
    try:
        target = (weights.get(TARGET_EXO) or {})
        hist = target.get("history") or []
        if not hist:
            print(f"  Pas d'entry pour '{TARGET_EXO}' dans stats_data.weights.")
        else:
            print(f"  current_weight={target.get('current_weight')}  last_reps={target.get('last_reps')}")
            print(f"  {'date':<12} {'weight':>8} {'reps':<18} {'1rm(API)':>10} {'1rm(recalc)':>12} sets_json?")
            for e in hist[:20]:
                d = e.get("date")
                w = float(e.get("weight") or 0)
                reps_str = str(e.get("reps") or "")
                orm_api = e.get("1rm") or 0
                # Recalc côté client sur reps max de la série (pour comparer)
                reps_list = [int(x) for x in reps_str.replace(",", " ").split() if x.strip().isdigit()]
                r_max = max(reps_list) if reps_list else 0
                orm_recalc = epley_or_brzycki(w, r_max)
                has_sets = bool(e.get("sets"))
                print(f"  {str(d)[:10]:<12} {w:>8.1f} {reps_str:<18} {orm_api:>10.1f} "
                      f"{orm_recalc:>12.1f} {'yes' if has_sets else 'no'}")
    except Exception as e:
        print(f"  ERROR: {e}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
