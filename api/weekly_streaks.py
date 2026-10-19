"""Source unique du streak hebdomadaire.

Extrait depuis /api/stats/streaks (routes/analytics_stats.py:api_stats_streaks)
pour être réutilisable par le DNA (workout_dna._compute_consistency) sans
dupliquer la logique. Toute modification de la définition du streak doit
passer par ici — plus de recalcul ad hoc ailleurs dans la codebase.

Jour actif = workout_sessions (completed OU rpe non-null), HIIT, cardio,
exercise_logs du jour. Semaine ISO (lundi → dimanche).
Semaine réussie = ≥ WEEKLY_TARGET jours actifs distincts.
Semaine en cours = ne casse pas le streak tant qu'elle n'est pas finie —
elle compte uniquement si elle a déjà atteint le target.
"""
from __future__ import annotations

import logging
from datetime import date as _date, timedelta as _td

import db as _db
from utils import _today_mtl, load_hiit_log

logger = logging.getLogger("trainingos.weekly_streaks")

WEEKLY_TARGET = 5


def _iso_monday(d: _date) -> _date:
    return d - _td(days=d.weekday())  # Mon=0 … Sun=6


def compute(today_str: str | None = None) -> dict:
    """Return the full weekly-streak payload for `today_str` (ISO date).

    Keys: weekly_target, weekly_streak_current, weekly_streak_best,
          week_at_risk, current_week, weeks (13 semaines, oldest first).
    """
    today_str = today_str or _today_mtl()
    try:
        today_date = _date.fromisoformat(today_str)
    except ValueError:
        today_date = _date.fromisoformat(_today_mtl())

    all_sessions = _db.get_workout_sessions(limit=730)
    session_dates: set[str] = set()
    for s in all_sessions:
        d = s.get("date")
        if not d:
            continue
        if s.get("completed") or s.get("rpe") is not None:
            session_dates.add(d)

    for h in load_hiit_log():
        d = h.get("date")
        if d:
            session_dates.add(d)

    for c in _db.get_cardio_logs(limit=730):
        d = c.get("date")
        if d:
            session_dates.add(d)

    # Today : include if exercise logs exist even without rpe/completed.
    try:
        today_exos = _db.get_session_exercise_logs(today_str)
    except Exception as e:
        logger.warning("get_session_exercise_logs failed: %s", e)
        today_exos = []
    if today_str in session_dates or bool(today_exos):
        session_dates.add(today_str)

    days_by_week: dict[_date, set[_date]] = {}
    for ds in session_dates:
        try:
            d = _date.fromisoformat(ds)
        except ValueError:
            continue
        days_by_week.setdefault(_iso_monday(d), set()).add(d)

    current_monday = _iso_monday(today_date)
    current_week_days = len(days_by_week.get(current_monday, set()))

    def _success(monday: _date) -> bool:
        return len(days_by_week.get(monday, set())) >= WEEKLY_TARGET

    # Streak courant — remonte à partir de la semaine en cours si elle a
    # atteint le target, sinon à partir de la précédente (la semaine en
    # cours ne casse pas tant qu'elle n'est pas finie).
    weekly_streak_current = 0
    m = current_monday if _success(current_monday) else current_monday - _td(days=7)
    while _success(m):
        weekly_streak_current += 1
        m -= _td(days=7)

    # Record historique : plus longue séquence consécutive de semaines
    # réussies. Semaine en cours éligible seulement si elle a atteint le
    # target (ne force pas un reset si incomplète).
    all_mondays = sorted(days_by_week.keys() | {current_monday})
    weekly_streak_best = 0
    cur = 0
    prev: _date | None = None
    for mon in all_mondays:
        if mon == current_monday and not _success(mon):
            continue
        if _success(mon):
            if prev is not None and (mon - prev).days == 7:
                cur += 1
            else:
                cur = 1
            weekly_streak_best = max(weekly_streak_best, cur)
        else:
            cur = 0
        prev = mon

    # weeks[] sur 13 semaines (12 précédentes + courante).
    weeks_payload = []
    oldest_monday = current_monday - _td(days=12 * 7)
    for i in range(13):
        wm = oldest_monday + _td(days=7 * i)
        days = len(days_by_week.get(wm, set()))
        weeks_payload.append({
            "week_start":  wm.isoformat(),
            "days_active": days,
            "success":     days >= WEEKLY_TARGET,
        })

    # week_at_risk — jours restants = (6 - weekday_today) + (1 si today pas actif).
    today_weekday = today_date.weekday()  # Mon=0, Sun=6
    today_active_in_week = today_date in days_by_week.get(current_monday, set())
    days_remaining = (6 - today_weekday) + (0 if today_active_in_week else 1)
    days_missing = max(0, WEEKLY_TARGET - current_week_days)
    week_at_risk = days_missing > 0 and days_remaining == days_missing

    return {
        "weekly_target":         WEEKLY_TARGET,
        "weekly_streak_current": weekly_streak_current,
        "weekly_streak_best":    weekly_streak_best,
        "week_at_risk":          week_at_risk,
        "current_week": {
            "week_start":  current_monday.isoformat(),
            "days_active": current_week_days,
        },
        "weeks": weeks_payload,
    }
