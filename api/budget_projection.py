"""Projection budgétaire — rythme réel/planifié + dates de mort projetées.

Rythme MESURÉ sur les périodes de paie complètes (period_end < today) depuis
PLAN_START (≥ MIN_PERIODS_FOR_MEASURED = 2). Sinon FALLBACK planifié avec
bascule calendaire au 1er octobre 2026 (fin du sprint voyage).
Projection séquentielle par attack_order. Intérêts non modélisés
(cohérent avec balance_cents — carnet de ménage).
"""
from __future__ import annotations
import math
from datetime import date, timedelta

import budget as _b

MIN_PERIODS_FOR_MEASURED = 2
PLANNED_ATTACK_SWITCH = date(2026, 10, 1)
PLANNED_ATTACK_BEFORE = 59750
PLANNED_ATTACK_AFTER  = 84750
PLANNED_FUND          = 25000
_PERIODS_PER_YEAR     = 24
_MAX_SEGMENTS         = 32           # ponytail: fallback = 2 segments, marge large.
_MAX_HORIZON_DAYS     = 365 * 30     # ponytail: >30 ans = None (rythme aberrant).


# ── Périodes complètes ──────────────────────────────────────────────────────

def _complete_periods_since(plan_start: date, today: date) -> list[tuple[date, date]]:
    """Périodes (start, end) dont end < today, depuis plan_start."""
    out: list[tuple[date, date]] = []
    start = plan_start
    while True:
        end = _b.next_payday(start) - timedelta(days=1)
        if end >= today:
            return out
        out.append((start, end))
        start = end + timedelta(days=1)


# ── Agrégations logs ────────────────────────────────────────────────────────

def _paid_by_debt(logs: list[dict]) -> dict:
    """Somme amount_cents groupé par debt_key (debt_payment + fund_transfer)."""
    out: dict = {}
    for row in logs:
        k = row.get("debt_key")
        if not k: continue
        out[k] = out.get(k, 0) + int(row.get("amount_cents") or 0)
    return out


def _measured_rates(today: date, logs: list[dict]) -> tuple[float, float] | None:
    """(attack_per_day, fund_per_day) si ≥ MIN périodes complètes, sinon None.
    Un rythme réel = 0 (mesuré) N'EST PAS un fallback — respect du fait mesuré."""
    periods = _complete_periods_since(_b.PLAN_START, today)
    if len(periods) < MIN_PERIODS_FOR_MEASURED:
        return None
    range_start = periods[0][0]
    range_end   = periods[-1][1]
    days_covered = (range_end - range_start).days + 1
    attack_total = 0
    fund_total   = 0
    for row in logs:
        d = date.fromisoformat(row["date"])
        if not (range_start <= d <= range_end): continue
        amount = int(row.get("amount_cents") or 0)
        t = row.get("type")
        if t == "debt_payment":
            attack_total += amount
        elif t == "fund_transfer":
            fund_total += amount
    return (attack_total / days_covered, fund_total / days_covered)


# ── Fonctions de rythme — rate_fn(d) → (rate_per_day, next_change|None) ─────

def _fallback_attack_rate_fn(d: date) -> tuple[float, date | None]:
    if d < PLANNED_ATTACK_SWITCH:
        return PLANNED_ATTACK_BEFORE * _PERIODS_PER_YEAR / 365, PLANNED_ATTACK_SWITCH
    return PLANNED_ATTACK_AFTER * _PERIODS_PER_YEAR / 365, None


def _fallback_fund_rate_fn(_d: date) -> tuple[float, date | None]:
    return PLANNED_FUND * _PERIODS_PER_YEAR / 365, None


def _constant_rate_fn(rate_per_day: float):
    return lambda _d: (rate_per_day, None)


# ── Projection ─────────────────────────────────────────────────────────────

def _project_forward(start: date, amount_cents: int, rate_fn) -> date | None:
    """Avance segment par segment depuis start jusqu'à couvrir amount_cents.
    rate_fn(d) → (rate/jour, prochain changement | None). rate<=0 → None.
    Horizon > _MAX_HORIZON_DAYS → None."""
    if amount_cents <= 0:
        return start
    remaining = float(amount_cents)
    d = start
    for _ in range(_MAX_SEGMENTS):
        rate, next_change = rate_fn(d)
        if rate <= 0:
            return None
        if next_change is None or next_change <= d:
            days_needed = math.ceil(remaining / rate)
            if days_needed > _MAX_HORIZON_DAYS: return None
            return d + timedelta(days=days_needed)
        span_days = (next_change - d).days
        segment_cap = rate * span_days
        if segment_cap >= remaining:
            days_needed = math.ceil(remaining / rate)
            if days_needed > _MAX_HORIZON_DAYS: return None
            return d + timedelta(days=days_needed)
        remaining -= segment_cap
        d = next_change
    return None


def _project_debt_deaths(debts_sorted: list[dict], paid_by_debt: dict,
                          rate_fn, today: date) -> dict:
    """{debt_key: death_date|None}, attaque séquentielle par attack_order.
    Dette morte (balance<=0) → death=None, dette suivante démarre today."""
    out: dict = {}
    available_from = today
    for d in debts_sorted:
        balance = int(d["initial_cents"]) - int(paid_by_debt.get(d["key"], 0))
        if balance <= 0:
            out[d["key"]] = None
            continue
        proj = _project_forward(available_from, balance, rate_fn)
        out[d["key"]] = proj
        available_from = (proj + timedelta(days=1)) if proj else today


    return out


def _project_fund_completion(fund_paid: int, target: int, rate_fn, today: date) -> date | None:
    remaining = target - fund_paid
    if remaining <= 0: return None
    return _project_forward(today, remaining, rate_fn)


def _project_fund_amount_at(start: date, deadline: date, current: int,
                              target: int, rate_fn) -> int:
    """Montant du fund à une date fixe, borné par target.
    Symétrique à _project_fund_completion (date→montant vs montant→date)."""
    if deadline <= start: return current
    if current >= target: return target
    gain = 0.0
    d = start
    days_left = (deadline - d).days
    for _ in range(_MAX_SEGMENTS):
        if days_left <= 0: break
        rate, next_change = rate_fn(d)
        if rate <= 0: break
        if next_change is None or next_change <= d:
            gain += rate * days_left
            break
        span = min((next_change - d).days, days_left)
        gain += rate * span
        days_left -= span
        d = next_change
    return min(current + int(round(gain)), target)


# ── Jalons ─────────────────────────────────────────────────────────────────

def _debt_thresholds(initial: int) -> list[int]:
    """Seuils décroissants 75/50/25/0."""
    return [initial * 3 // 4, initial // 2, initial // 4, 0]


def _fund_thresholds(target: int) -> list[int]:
    """Seuils croissants 25/50/75/100."""
    return [target // 4, target // 2, target * 3 // 4, target]


def _debt_active(debts_sorted: list[dict], paid_by_debt: dict) -> dict | None:
    """Première dette avec balance > 0 selon attack_order."""
    for d in debts_sorted:
        balance = int(d["initial_cents"]) - int(paid_by_debt.get(d["key"], 0))
        if balance > 0: return d
    return None


def _next_milestone(debts_sorted: list[dict], paid_by_debt: dict,
                     fund: dict | None, fund_paid: int,
                     rate_fn_attack, rate_fn_fund, today: date) -> dict | None:
    """Un seul jalon retourné : le plus proche en date parmi dette active + fund."""
    candidates: list[dict] = []

    active = _debt_active(debts_sorted, paid_by_debt)
    if active is not None:
        initial = int(active["initial_cents"])
        balance = initial - int(paid_by_debt.get(active["key"], 0))
        for thr in _debt_thresholds(initial):
            if balance > thr:
                proj = _project_forward(today, balance - thr, rate_fn_attack)
                if proj is not None:
                    candidates.append({
                        "kind": "debt_death" if thr == 0 else "debt_threshold",
                        "key":  active["key"],
                        "threshold_cents": thr,
                        "projected_date": proj,
                    })
                break

    if fund is not None:
        target = int(fund.get("target_cents") or 0)
        if target > 0 and fund_paid < target:
            for thr in _fund_thresholds(target):
                if fund_paid < thr:
                    proj = _project_forward(today, thr - fund_paid, rate_fn_fund)
                    if proj is not None:
                        candidates.append({
                            "kind": "fund_complete" if thr == target else "fund_quarter",
                            "key":  fund["key"],
                            "threshold_cents": thr,
                            "projected_date": proj,
                        })
                    break

    if not candidates:
        return None
    return min(candidates, key=lambda c: c["projected_date"])


# ── Entry point ────────────────────────────────────────────────────────────

def compute(today: date, envelopes: list, debts: list, logs: list) -> dict:
    """Retourne les champs projection à fusionner dans compute_status()."""
    paid_by_debt = _paid_by_debt(logs)

    measured = _measured_rates(today, logs)
    if measured is None:
        rate_fn_attack = _fallback_attack_rate_fn
        rate_fn_fund   = _fallback_fund_rate_fn
        attack_pd, _   = _fallback_attack_rate_fn(today)
        fund_pd,   _   = _fallback_fund_rate_fn(today)
        is_fallback = True
    else:
        attack_pd, fund_pd = measured
        rate_fn_attack = _constant_rate_fn(attack_pd)
        rate_fn_fund   = _constant_rate_fn(fund_pd)
        is_fallback = False

    non_savings_sorted = sorted([d for d in debts if not d["is_savings"]],
                                 key=lambda x: x["attack_order"])
    death_dates = _project_debt_deaths(non_savings_sorted, paid_by_debt, rate_fn_attack, today)

    fund = next((d for d in debts if d["is_savings"]), None)
    fund_paid = int(paid_by_debt.get(fund["key"], 0)) if fund else 0
    fund_completion = None
    fund_deadline_iso: str | None = None
    fund_at_deadline: int | None = None
    if fund is not None:
        target = int(fund.get("target_cents") or 0)
        if target > 0:
            fund_completion = _project_fund_completion(fund_paid, target, rate_fn_fund, today)
        fund_deadline_iso = fund.get("deadline_date")
        if fund_deadline_iso and target > 0:
            deadline_d = date.fromisoformat(fund_deadline_iso)
            fund_at_deadline = _project_fund_amount_at(
                today, deadline_d, fund_paid, target, rate_fn_fund
            )

    milestone = _next_milestone(non_savings_sorted, paid_by_debt,
                                 fund, fund_paid, rate_fn_attack, rate_fn_fund, today)

    return {
        "paid_by_debt": paid_by_debt,
        "projection": {
            "attack_rate_cents_per_day": int(round(attack_pd)),
            "fund_rate_cents_per_day":   int(round(fund_pd)),
            "is_fallback_rate":          is_fallback,
        },
        "death_dates":     {k: (v.isoformat() if v else None) for k, v in death_dates.items()},
        "fund_completion": fund_completion.isoformat() if fund_completion else None,
        "fund_deadline":   fund_deadline_iso,
        "fund_at_deadline": fund_at_deadline,
        "next_milestone":  _milestone_payload(milestone, today),
    }


def _milestone_payload(m: dict | None, today: date) -> dict | None:
    if m is None: return None
    return {
        "kind":            m["kind"],
        "key":             m["key"],
        "threshold_cents": m["threshold_cents"],
        "projected_date":  m["projected_date"].isoformat(),
        "days_remaining":  (m["projected_date"] - today).days,
    }
