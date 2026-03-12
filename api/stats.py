from __future__ import annotations
from collections import defaultdict
from datetime import datetime
from db import get_json


# ─────────────────────────────────────────────────────────────
# LOADERS
# ─────────────────────────────────────────────────────────────

def load_weights() -> dict:
    return get_json("weights", {}) or {}

def load_hiit_log() -> list:
    return get_json("hiit_log", []) or []

def load_inventory() -> dict:
    return get_json("inventory", {}) or {}

def load_body_weight() -> list:
    return get_json("body_weight", []) or []


# ─────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────

def week_key(date_str: str) -> str:
    return datetime.strptime(date_str, "%Y-%m-%d").strftime("%Y-S%W")

def parse_reps(reps_str: str) -> list[int]:
    return [int(r) for r in str(reps_str).split(",") if r.strip().isdigit()]


# ─────────────────────────────────────────────────────────────
# MUSCU — graphiques existants nettoyés
# ─────────────────────────────────────────────────────────────

def compute_volume_par_seance(weights: dict) -> list[dict]:
    vol = defaultdict(float)
    for ex, data in weights.items():
        for entry in data.get("history", []):
            try:
                reps = parse_reps(entry.get("reps", ""))
                vol[entry["date"]] += entry.get("weight", 0) * sum(reps)
            except Exception:
                continue
    return [{"date": d, "volume": round(v, 1)} for d, v in sorted(vol.items())]


def compute_volume_par_semaine(volume_par_seance: list[dict]) -> list[dict]:
    vol = defaultdict(float)
    for e in volume_par_seance:
        vol[week_key(e["date"])] += e["volume"]
    return [{"semaine": s, "volume": round(v, 1)} for s, v in sorted(vol.items())]


def compute_frequence_par_semaine(weights: dict, hiit_log: list) -> list[dict]:
    """Jours d'entraînement distincts par semaine (muscu + HIIT)."""
    jours: dict[str, set] = defaultdict(set)
    for ex, data in weights.items():
        for entry in data.get("history", []):
            d = entry.get("date", "")
            if d:
                jours[week_key(d)].add(d)
    for e in hiit_log:
        d = e.get("date", "")
        if d:
            jours[week_key(d)].add(d)
    return [{"semaine": s, "seances": len(days)} for s, days in sorted(jours.items())]


def compute_rpe_par_seance(sessions: dict) -> list[dict]:
    return [
        {"date": d, "rpe": s["rpe"]}
        for d, s in sorted(sessions.items())
        if s.get("rpe")
    ]


# ─────────────────────────────────────────────────────────────
# MUSCU — nouveaux graphiques
# ─────────────────────────────────────────────────────────────

def compute_1rm_progression(weights: dict, top_n: int = 5) -> dict[str, list[dict]]:
    """1RM estimé (Epley) dans le temps pour les top_n exercices les plus fréquents."""
    counts  = {ex: len(data.get("history", [])) for ex, data in weights.items()}
    top_exos = sorted(counts, key=counts.get, reverse=True)[:top_n]

    result = {}
    for ex in top_exos:
        pts = []
        for entry in sorted(weights[ex].get("history", []), key=lambda e: e.get("date", "")):
            try:
                w    = entry.get("weight", 0)
                reps = parse_reps(entry.get("reps", ""))
                if not reps or not w:
                    continue
                avg_reps = sum(reps) / len(reps)
                orm      = round(w * (1 + avg_reps / 30), 1)
                pts.append({"date": entry["date"], "1rm": orm})
            except Exception:
                continue
        if pts:
            result[ex] = pts
    return result


def compute_intensite_relative(weights: dict) -> list[dict]:
    """Intensité relative moyenne par séance = poids / 1RM récent (%)."""
    recents_1rm: dict[str, float] = {}
    for ex, data in weights.items():
        history = sorted(data.get("history", []), key=lambda e: e.get("date", ""), reverse=True)
        for entry in history[:3]:
            try:
                w    = entry.get("weight", 0)
                reps = parse_reps(entry.get("reps", ""))
                if w and reps:
                    recents_1rm[ex] = round(w * (1 + sum(reps) / len(reps) / 30), 1)
                    break
            except Exception:
                continue

    intensite: dict[str, list[float]] = defaultdict(list)
    for ex, data in weights.items():
        if ex not in recents_1rm:
            continue
        for entry in data.get("history", []):
            try:
                w   = entry.get("weight", 0)
                orm = recents_1rm[ex]
                if w and orm:
                    intensite[entry["date"]].append(w / orm * 100)
            except Exception:
                continue

    return [
        {"date": d, "intensite": round(sum(vals) / len(vals), 1)}
        for d, vals in sorted(intensite.items()) if vals
    ]


def compute_ratio_push_pull_legs(weights: dict, inventory: dict) -> list[dict]:
    """Volume push/pull/legs/core par semaine pour stacked bar."""
    data: dict[str, dict[str, float]] = defaultdict(lambda: defaultdict(float))
    for ex, exdata in weights.items():
        cat = inventory.get(ex, {}).get("category", "")
        if cat not in ("push", "pull", "legs", "core"):
            continue
        for entry in exdata.get("history", []):
            try:
                reps = parse_reps(entry.get("reps", ""))
                vol  = entry.get("weight", 0) * sum(reps)
                data[week_key(entry["date"])][cat] += vol
            except Exception:
                continue

    return [
        {
            "semaine": wk,
            "push":  round(data[wk].get("push", 0)),
            "pull":  round(data[wk].get("pull", 0)),
            "legs":  round(data[wk].get("legs", 0)),
            "core":  round(data[wk].get("core", 0)),
        }
        for wk in sorted(data)
    ]


def compute_top5_volume(weights: dict) -> list[dict]:
    """Top 5 exercices par volume cumulé total."""
    totals: dict[str, float] = defaultdict(float)
    for ex, data in weights.items():
        for entry in data.get("history", []):
            try:
                reps = parse_reps(entry.get("reps", ""))
                totals[ex] += entry.get("weight", 0) * sum(reps)
            except Exception:
                continue
    top5 = sorted(totals.items(), key=lambda x: x[1], reverse=True)[:5]
    return [{"exercise": ex, "volume": round(v)} for ex, v in top5]


def compute_rpe_vs_volume(weights: dict, sessions: dict) -> list[dict]:
    """Scatter RPE vs volume par séance."""
    vol_map = {e["date"]: e["volume"] for e in compute_volume_par_seance(weights)}
    return [
        {"date": d, "rpe": s["rpe"], "volume": vol_map[d]}
        for d, s in sorted(sessions.items())
        if s.get("rpe") and d in vol_map
    ]


# ─────────────────────────────────────────────────────────────
# HIIT
# ─────────────────────────────────────────────────────────────

def compute_hiit_rounds(hiit_log: list) -> list[dict]:
    return [
        {
            "date":      e["date"],
            "completes": e.get("rounds_completes", e.get("rounds_complétés", 0)),
            "planifies":  e.get("rounds_planifies", e.get("rounds_planifiés", 0)),
        }
        for e in sorted(hiit_log, key=lambda x: x.get("date", ""))
    ]


def compute_hiit_vitesse(hiit_log: list) -> list[dict]:
    """Progression vitesse sprint max et croisière."""
    return [
        {
            "date":      e["date"],
            "sprint":    e.get("vitesse_max"),
            "croisiere": e.get("vitesse_croisiere"),
        }
        for e in sorted(hiit_log, key=lambda x: x.get("date", ""))
        if e.get("vitesse_max") or e.get("vitesse_croisiere")
    ]


def compute_hiit_rpe(hiit_log: list) -> list[dict]:
    return [
        {"date": e["date"], "rpe": e["rpe"]}
        for e in sorted(hiit_log, key=lambda x: x.get("date", ""))
        if e.get("rpe")
    ]


# ─────────────────────────────────────────────────────────────
# POIDS CORPOREL
# ─────────────────────────────────────────────────────────────

def compute_courbe_poids(body_weight: list) -> list[dict]:
    return [
        {"date": e["date"], "poids": e["poids"]}
        for e in sorted(body_weight, key=lambda x: x.get("date", ""))
    ]