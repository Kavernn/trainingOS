"""
self_care.py — Habitudes self-care quotidiennes + streaks.

Clés KV :
  "self_care_habits" → list[dict]  (configuration personnalisée)
  "self_care_log"    → dict {date: [habit_id, ...]}

Endpoints exposés dans index.py :
  GET    /api/self_care/habits
  POST   /api/self_care/habits
  DELETE /api/self_care/habits/<id>
  POST   /api/self_care/log
  GET    /api/self_care/today
  GET    /api/self_care/streaks
"""
from __future__ import annotations

from datetime import date as date_cls, timedelta
import uuid

from db import get_json, set_json

_HABITS_KEY = "self_care_habits"
_LOG_KEY    = "self_care_log"

# ── Habitudes par défaut ──────────────────────────────────────────────────────

DEFAULT_HABITS = [
    {"id": "walk",      "name": "Marcher 20 min",        "icon": "figure.walk",          "category": "physique",  "is_default": True},
    {"id": "water",     "name": "Boire 2 L d'eau",       "icon": "drop.fill",            "category": "physique",  "is_default": True},
    {"id": "sleep7",    "name": "Dormir 7h+",            "icon": "moon.fill",            "category": "sommeil",   "is_default": True},
    {"id": "meditate",  "name": "Méditer 5 min",         "icon": "brain.head.profile",   "category": "mental",    "is_default": True},
    {"id": "read",      "name": "Lire 20 min",           "icon": "book.fill",            "category": "mental",    "is_default": True},
    {"id": "social",    "name": "Appeler un ami",        "icon": "phone.fill",           "category": "social",    "is_default": False},
    {"id": "meals",     "name": "Manger 3 repas",        "icon": "fork.knife",           "category": "physique",  "is_default": False},
    {"id": "noscreen",  "name": "Pas d'écran 1h avant dodo", "icon": "moon.zzz.fill",   "category": "sommeil",   "is_default": False},
    {"id": "gratitude", "name": "Écrire 3 gratitudes",  "icon": "heart.fill",           "category": "mental",    "is_default": False},
    {"id": "stretch",   "name": "S'étirer 10 min",      "icon": "figure.flexibility",   "category": "physique",  "is_default": False},
]


# ── Stockage ──────────────────────────────────────────────────────────────────

def _load_habits() -> list:
    stored = get_json(_HABITS_KEY)
    if stored is None:
        # Premier accès → initialiser avec les habitudes par défaut actives
        defaults = [h for h in DEFAULT_HABITS if h["is_default"]]
        set_json(_HABITS_KEY, defaults)
        return defaults
    return stored

def _save_habits(habits: list) -> None:
    set_json(_HABITS_KEY, habits)

def _load_log() -> dict:
    return get_json(_LOG_KEY) or {}

def _save_log(log: dict) -> None:
    set_json(_LOG_KEY, log)


# ── Habitudes ─────────────────────────────────────────────────────────────────

def get_habits() -> list:
    return _load_habits()

def add_habit(name: str, icon: str = "star.fill", category: str = "mental") -> dict:
    habits = _load_habits()
    habit = {
        "id":         str(uuid.uuid4()),
        "name":       name,
        "icon":       icon,
        "category":   category,
        "is_default": False,
    }
    habits.append(habit)
    _save_habits(habits)
    return habit

def delete_habit(habit_id: str) -> bool:
    habits = _load_habits()
    new = [h for h in habits if h["id"] != habit_id]
    if len(new) == len(habits):
        return False
    _save_habits(new)
    # Retirer du log aussi
    log = _load_log()
    for date_key in log:
        log[date_key] = [h for h in log[date_key] if h != habit_id]
    _save_log(log)
    return True


# ── Log quotidien ─────────────────────────────────────────────────────────────

def log_today(habit_ids: list[str]) -> dict:
    """Remplace le log du jour par la liste fournie."""
    log  = _load_log()
    today = date_cls.today().isoformat()
    valid_ids = {h["id"] for h in _load_habits()}
    log[today] = [hid for hid in habit_ids if hid in valid_ids]
    _save_log(log)
    return get_today_status()

def get_today_status() -> dict:
    today   = date_cls.today().isoformat()
    habits  = _load_habits()
    log     = _load_log()
    done    = set(log.get(today, []))
    return {
        "date":      today,
        "habits":    habits,
        "completed": list(done),
        "rate":      round(len(done) / len(habits), 2) if habits else 0,
    }


# ── Streaks ───────────────────────────────────────────────────────────────────

def get_streaks() -> list[dict]:
    """Calcule le streak courant et max pour chaque habitude."""
    habits = _load_habits()
    log    = _load_log()
    today  = date_cls.today()
    result = []

    for habit in habits:
        hid     = habit["id"]
        streak  = 0
        longest = 0
        current = 0

        # Parcours DESC depuis aujourd'hui
        d = today
        for _ in range(90):
            key  = d.isoformat()
            done = hid in log.get(key, [])
            if done:
                current += 1
                longest  = max(longest, current)
                if d >= today - timedelta(days=1):
                    streak = current
            else:
                if d < today:
                    if streak == 0:
                        streak = 0
                    current = 0
            d -= timedelta(days=1)

        result.append({
            "habit_id":      hid,
            "habit_name":    habit["name"],
            "habit_icon":    habit["icon"],
            "current_streak": streak,
            "longest_streak": longest,
        })

    return sorted(result, key=lambda x: x["current_streak"], reverse=True)


def get_completion_rate(days: int = 7) -> float:
    """Taux de complétion moyen sur N jours."""
    habits = _load_habits()
    if not habits:
        return 0.0
    log = _load_log()
    today = date_cls.today()
    totals = []
    for i in range(days):
        key  = (today - timedelta(days=i)).isoformat()
        done = len(log.get(key, []))
        totals.append(done / len(habits))
    return round(sum(totals) / len(totals), 2) if totals else 0.0
