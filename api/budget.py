"""Budget — logique de période paie + backfill idempotent + payload status.

Période budgétaire = par paie (15 et jour_paie_2 mensuel).
jour_paie_2 = min(30, dernier jour du mois) — février → 28, mars → 30, etc.
Backfill borné à PLAN_START = 2026-07-15 (aucun log rétroactif au-delà).
"""
from __future__ import annotations
import calendar, logging
from datetime import date, timedelta

from utils import _today_mtl_date
import db_budget

logger = logging.getLogger("trainingos.budget")

PAIE_CENTS = 174391
PLAN_START = date(2026, 7, 15)


def _paydays_for_month(year: int, month: int) -> tuple[date, date]:
    """Retourne (paie_1, paie_2) : le 15 et min(30, dernier_jour)."""
    last = calendar.monthrange(year, month)[1]
    return date(year, month, 15), date(year, month, min(30, last))


def current_period_start(today: date) -> date:
    """Début de la période courante = paie la plus récente ≤ today."""
    p1, p2 = _paydays_for_month(today.year, today.month)
    if today >= p2: return p2
    if today >= p1: return p1
    prev = today.replace(day=1) - timedelta(days=1)
    _, prev_p2 = _paydays_for_month(prev.year, prev.month)
    return prev_p2


def next_payday(today: date) -> date:
    """Prochaine paie strictement > today."""
    p1, p2 = _paydays_for_month(today.year, today.month)
    if today < p1: return p1
    if today < p2: return p2
    if today.month == 12: return date(today.year + 1, 1, 15)
    return date(today.year, today.month + 1, 15)


def _paydays_between(start: date, end: date):
    """Yield toutes les paies (15 et jour_paie_2) dans [start, end]."""
    if start > end: return
    y, m = start.year, start.month
    while date(y, m, 1) <= end:
        p1, p2 = _paydays_for_month(y, m)
        if start <= p1 <= end: yield p1
        if start <= p2 <= end: yield p2
        m += 1
        if m > 12: m, y = 1, y + 1


def backfill_incomes(today: date | None = None) -> int:
    """Insère les paies manquantes de PLAN_START jusqu'à today.
    Idempotent (partial unique index). Retourne le nb inséré."""
    today = today or _today_mtl_date()
    last_str = db_budget.get_last_income_date()
    last = date.fromisoformat(last_str) if last_str else None
    start = max(last + timedelta(days=1) if last else PLAN_START, PLAN_START)
    inserted = 0
    for pd in _paydays_between(start, today):
        if db_budget.insert_income_if_absent(pd.isoformat(), PAIE_CENTS):
            inserted += 1
    return inserted


def compute_status() -> dict:
    """Payload GET /api/budget/status."""
    today = _today_mtl_date()
    backfill_incomes(today)
    start = current_period_start(today)
    end   = next_payday(today) - timedelta(days=1)

    envelopes = db_budget.get_envelopes()
    period_expenses = db_budget.sum_expenses_by_envelope(start.isoformat(), end.isoformat())
    envelope_status = []
    for e in envelopes:
        period_limit = e["limit_cents"] // 2
        spent = period_expenses.get(e["key"], 0)
        envelope_status.append({
            "key":              e["key"],
            "label":            e["label"],
            "limit_cents":      period_limit,
            "spent_cents":      spent,
            "remaining_cents":  period_limit - spent,
        })

    debts = db_budget.get_debt_accounts()
    debt_status = []
    for d in debts:
        paid = db_budget.sum_debt_payments(d["key"])
        if d["is_savings"]:
            target = d["target_cents"] or 0
            debt_status.append({
                "key":           d["key"],
                "label":         d["label"],
                "is_savings":    True,
                "current_cents": paid,
                "target_cents":  target,
                "progress_pct":  round(100 * paid / target, 1) if target else 0.0,
            })
        else:
            debt_status.append({
                "key":           d["key"],
                "label":         d["label"],
                "is_savings":    False,
                "balance_cents": d["initial_cents"] - paid,
                "initial_cents": d["initial_cents"],
                "interest_rate": float(d["interest_rate"]) if d.get("interest_rate") is not None else None,
                "attack_order":  d["attack_order"],
            })

    return {
        "period_start":         start.isoformat(),
        "period_end":           end.isoformat(),
        "days_to_next_payday":  (next_payday(today) - today).days,
        "envelopes":            envelope_status,
        "debts":                debt_status,
    }
