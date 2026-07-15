"""Tests purs (pas de DB) : moteur de projection budgétaire.

Cas couverts (rapport A5 + bascule 2026-10-01) :
- Fallback avant 2 périodes complètes (aujourd'hui = 2026-07-11)
- Bords de bascule 2026-09-30 vs 2026-10-01 (fallback attack rate)
- _project_forward qui traverse la bascule (segments multiples)
- Rythme réel = 0 avec ≥2 périodes → NOT fallback (respect du fait mesuré)
- Dette 1 morte → dette 2 démarre today
- Fund atteint → completion=null, milestone bascule sur dette
- Séquentiel : death carte > death découvert
- Milestone dédoublonnage : dernier seuil = mort → kind='debt_death'
- rate=0 → aucun ZeroDivisionError
- _paid_by_debt : agrégation debt_payment + fund_transfer
"""
from datetime import date

import budget_projection as bp


# ── Constantes de test ──────────────────────────────────────────────────────

DECOUVERT_INITIAL = 210000
CARTE_INITIAL     = 1364000
FUND_TARGET       = 150000

DEBTS = [
    {"key": "decouvert",    "initial_cents": DECOUVERT_INITIAL, "attack_order": 1, "is_savings": False, "target_cents": None},
    {"key": "carte",        "initial_cents": CARTE_INITIAL,     "attack_order": 2, "is_savings": False, "target_cents": None},
    {"key": "fonds_voyage", "initial_cents": 0,                 "attack_order": None, "is_savings": True, "target_cents": FUND_TARGET},
]


# ── _paid_by_debt ───────────────────────────────────────────────────────────

def test_paid_by_debt_aggregates_debt_payment_and_fund_transfer():
    logs = [
        {"date": "2026-07-16", "type": "fund_transfer", "debt_key": "fonds_voyage", "amount_cents": 5000},
        {"date": "2026-07-17", "type": "fund_transfer", "debt_key": "fonds_voyage", "amount_cents": 3000},
        {"date": "2026-07-19", "type": "debt_payment",  "debt_key": "decouvert",    "amount_cents": 12000},
    ]
    assert bp._paid_by_debt(logs) == {"fonds_voyage": 8000, "decouvert": 12000}


def test_paid_by_debt_ignores_rows_without_debt_key():
    logs = [
        {"date": "2026-07-16", "type": "expense", "envelope_key": "epicerie", "amount_cents": 4000},
        {"date": "2026-07-17", "type": "debt_payment", "debt_key": "decouvert", "amount_cents": 1000},
    ]
    assert bp._paid_by_debt(logs) == {"decouvert": 1000}


# ── _complete_periods_since ─────────────────────────────────────────────────

def test_complete_periods_empty_before_plan_start():
    assert bp._complete_periods_since(date(2026, 7, 15), date(2026, 7, 11)) == []


def test_complete_periods_one_after_first_payday():
    # Aujourd'hui 2026-07-30 : période 1 (15-29 juil) terminée hier.
    periods = bp._complete_periods_since(date(2026, 7, 15), date(2026, 7, 30))
    assert periods == [(date(2026, 7, 15), date(2026, 7, 29))]


def test_complete_periods_two_after_second_payday():
    # Note : 15 août 2026 = samedi → p1 août ajusté au vendredi 14 août.
    # Donc period 2 se termine le 2026-08-13 (veille de la paie avancée).
    periods = bp._complete_periods_since(date(2026, 7, 15), date(2026, 8, 15))
    assert periods == [
        (date(2026, 7, 15), date(2026, 7, 29)),
        (date(2026, 7, 30), date(2026, 8, 13)),
    ]


# ── Rate function bascule (bord exact 2026-10-01) ───────────────────────────

def test_fallback_attack_before_switch():
    rate, nxt = bp._fallback_attack_rate_fn(date(2026, 9, 12))
    assert rate == bp.PLANNED_ATTACK_BEFORE * 24 / 365
    assert nxt == date(2026, 9, 13)


def test_fallback_attack_on_switch():
    rate, nxt = bp._fallback_attack_rate_fn(date(2026, 9, 13))
    assert rate == bp.PLANNED_ATTACK_AFTER * 24 / 365
    assert nxt is None


def test_fallback_fund_constant():
    rate, nxt = bp._fallback_fund_rate_fn(date(2026, 7, 11))
    assert rate == bp.PLANNED_FUND * 24 / 365
    assert nxt is None


# ── _project_forward ────────────────────────────────────────────────────────

def test_project_forward_zero_amount_returns_start():
    assert bp._project_forward(date(2026, 7, 11), 0, bp._constant_rate_fn(100.0)) == date(2026, 7, 11)


def test_project_forward_negative_amount_returns_start():
    assert bp._project_forward(date(2026, 7, 11), -500, bp._constant_rate_fn(100.0)) == date(2026, 7, 11)


def test_project_forward_zero_rate_returns_none():
    assert bp._project_forward(date(2026, 7, 11), 1000, bp._constant_rate_fn(0.0)) is None


def test_project_forward_constant_rate_single_segment():
    # 1000 cents at 100/day = 10 days.
    result = bp._project_forward(date(2026, 7, 11), 1000, bp._constant_rate_fn(100.0))
    assert result == date(2026, 7, 21)


def test_project_forward_traverses_bascule_2026_09_13():
    """Valeurs calculées à la main pour prouver la traversée segment par segment.
    Rythme pré-départ = 45781 * 24 / 365 = 3010.269 c/j.
    Rythme post-départ = 83281 * 24 / 365 = 5476.833 c/j.
    Segment 1 (2026-08-15 → 2026-09-13, 29 j × 3010.269) : 87 297.79 cents.
    Segment 2 (dès 2026-09-13, 5476.833 c/j) : reste 122 702.21 → ceil(22.4047) = 23 j.
    2026-09-13 + 23 j = 2026-10-06."""
    death = bp._project_forward(date(2026, 8, 15), 210000, bp._fallback_attack_rate_fn)
    assert death == date(2026, 10, 6)


# ── compute() : fallback vs measured ────────────────────────────────────────

def test_compute_fallback_before_plan_start():
    """Aujourd'hui 2026-07-11 : 0 période complète → fallback, attack pré-oct."""
    proj = bp.compute(date(2026, 7, 11), [], DEBTS, [])
    assert proj["projection"]["is_fallback_rate"] is True
    assert proj["projection"]["attack_rate_cents_per_day"] == int(round(bp.PLANNED_ATTACK_BEFORE * 24 / 365))
    assert proj["projection"]["fund_rate_cents_per_day"] == int(round(bp.PLANNED_FUND * 24 / 365))


def test_compute_fallback_with_one_complete_period():
    """1 période complète (<2) → toujours fallback."""
    proj = bp.compute(date(2026, 7, 30), [], DEBTS, [])
    assert proj["projection"]["is_fallback_rate"] is True


def test_compute_measured_when_two_periods_and_data():
    """2 périodes complètes + données → measured (is_fallback=False).
    Range = 2026-07-15 → 2026-08-13 (30 jours, cf weekend shift 15 août = sam)."""
    logs = [
        {"date": "2026-07-20", "type": "debt_payment",  "debt_key": "decouvert",    "amount_cents": 30000},
        {"date": "2026-08-05", "type": "fund_transfer", "debt_key": "fonds_voyage", "amount_cents": 15000},
    ]
    proj = bp.compute(date(2026, 8, 15), [], DEBTS, logs)
    assert proj["projection"]["is_fallback_rate"] is False
    assert proj["projection"]["attack_rate_cents_per_day"] == 1000  # 30000 / 30
    assert proj["projection"]["fund_rate_cents_per_day"] == 500     # 15000 / 30


def test_compute_measured_zero_is_not_fallback():
    """≥2 périodes complètes ET rythme mesuré = 0 → NOT fallback, projections=null.
    Le fallback signifie 'pas encore de données', jamais 'données déplaisantes'."""
    proj = bp.compute(date(2026, 8, 15), [], DEBTS, [])
    assert proj["projection"]["is_fallback_rate"] is False
    assert proj["projection"]["attack_rate_cents_per_day"] == 0
    assert proj["projection"]["fund_rate_cents_per_day"] == 0
    assert proj["death_dates"]["decouvert"] is None
    assert proj["death_dates"]["carte"] is None
    assert proj["fund_completion"] is None
    assert proj["next_milestone"] is None  # aucun candidat n'a de rate > 0


# ── Séquentiel / dettes ─────────────────────────────────────────────────────

def test_compute_debt_1_dead_advances_debt_2_from_today():
    """Découvert soldé → death=null, carte démarre today (available_from=today)."""
    logs = [
        {"date": "2026-07-16", "type": "debt_payment", "debt_key": "decouvert", "amount_cents": DECOUVERT_INITIAL},
    ]
    proj = bp.compute(date(2026, 7, 11), [], DEBTS, logs)  # fallback (0 périodes)
    assert proj["death_dates"]["decouvert"] is None
    assert proj["death_dates"]["carte"] is not None


def test_compute_sequential_debt_2_dies_after_debt_1():
    """Ordre : carte (attack_order=2) meurt strictement après découvert."""
    logs = [
        {"date": "2026-07-20", "type": "debt_payment", "debt_key": "decouvert", "amount_cents": 20000},
    ]
    proj = bp.compute(date(2026, 8, 15), [], DEBTS, logs)  # measured, rate ≈ 20000/31
    d1 = proj["death_dates"]["decouvert"]
    d2 = proj["death_dates"]["carte"]
    assert d1 is not None and d2 is not None
    assert d2 > d1  # ISO YYYY-MM-DD → tri lexico = tri chrono


# ── Fund atteint ────────────────────────────────────────────────────────────

def test_compute_fund_reached_no_completion_milestone_falls_to_debt():
    """Fund atteint → completion=null, prochain jalon = dette active."""
    logs = [
        {"date": "2026-07-16", "type": "fund_transfer", "debt_key": "fonds_voyage", "amount_cents": FUND_TARGET},
        {"date": "2026-07-20", "type": "debt_payment",  "debt_key": "decouvert",    "amount_cents": 30000},
    ]
    proj = bp.compute(date(2026, 8, 15), [], DEBTS, logs)
    assert proj["fund_completion"] is None
    assert proj["next_milestone"] is not None
    assert proj["next_milestone"]["kind"] in ("debt_threshold", "debt_death")


# ── Milestone dédoublonnage ─────────────────────────────────────────────────

def test_compute_milestone_debt_death_when_next_threshold_is_zero():
    """Balance < 25 % initial → prochain seuil = 0 → kind='debt_death'."""
    # Balance = 210000 - 160000 = 50000. Seuil 25 % = 52500 déjà franchi → prochain = 0.
    logs = [
        {"date": "2026-07-20", "type": "debt_payment", "debt_key": "decouvert", "amount_cents": 160000},
    ]
    proj = bp.compute(date(2026, 8, 15), [], DEBTS, logs)
    assert proj["next_milestone"]["kind"] == "debt_death"
    assert proj["next_milestone"]["key"] == "decouvert"
    assert proj["next_milestone"]["threshold_cents"] == 0


def test_compute_milestone_debt_threshold_normal_case():
    """Balance juste sous initial → prochain seuil = 75 %."""
    logs = [
        {"date": "2026-07-20", "type": "debt_payment", "debt_key": "decouvert", "amount_cents": 30000},
    ]
    proj = bp.compute(date(2026, 8, 15), [], DEBTS, logs)
    # Balance = 180000. Seuil 75 % de 210000 = 157500. 180000 > 157500 → next = 157500.
    m = proj["next_milestone"]
    assert m["kind"] == "debt_threshold"
    assert m["threshold_cents"] == 157500


# ── _project_fund_amount_at ─────────────────────────────────────────────────

def test_fund_amount_at_deadline_past_returns_current():
    """Deadline < start → montant courant tel quel."""
    assert bp._project_fund_amount_at(
        date(2026, 7, 11), date(2026, 7, 10), 5000, 150000, bp._constant_rate_fn(100.0)
    ) == 5000


def test_fund_amount_at_already_at_target_returns_target():
    """current ≥ target → target (clamp)."""
    assert bp._project_fund_amount_at(
        date(2026, 7, 11), date(2026, 8, 11), 150000, 150000, bp._constant_rate_fn(100.0)
    ) == 150000


def test_fund_amount_at_rate_zero_returns_current():
    """rate = 0 → aucune accumulation."""
    assert bp._project_fund_amount_at(
        date(2026, 7, 11), date(2026, 8, 11), 5000, 150000, bp._constant_rate_fn(0.0)
    ) == 5000


def test_fund_amount_at_partial_accumulation_below_target():
    """rate × days < remaining → current + gain, non clampé."""
    # 30 j × 100/j = 3000 gain. current 5000 → 8000. Target 150000 non atteint.
    assert bp._project_fund_amount_at(
        date(2026, 7, 11), date(2026, 8, 10), 5000, 150000, bp._constant_rate_fn(100.0)
    ) == 8000


def test_fund_amount_at_clamped_at_target():
    """rate × days > remaining → clamp à target."""
    # 100 j × 2000/j = 200000. current 5000 → 205000 → clamp 150000.
    assert bp._project_fund_amount_at(
        date(2026, 7, 11), date(2026, 10, 19), 5000, 150000, bp._constant_rate_fn(2000.0)
    ) == 150000


def test_fund_amount_at_constant_rate_no_switch():
    """Rate constant sans changement → segment unique linéaire."""
    # PLANNED_FUND * 24 / 365 ≈ 1643.84 c/j × 30 j.
    result = bp._project_fund_amount_at(
        date(2026, 7, 11), date(2026, 8, 10), 0, 150000, bp._fallback_fund_rate_fn
    )
    expected = int(round(bp.PLANNED_FUND * 24 / 365 * 30))
    assert result == expected


def test_compute_fund_deadline_and_at_deadline_in_payload():
    """Contrat additif : quand fund a deadline_date, compute retourne les 2 nouvelles clés."""
    debts_with_deadline = [
        {"key": "decouvert",    "initial_cents": DECOUVERT_INITIAL, "attack_order": 1, "is_savings": False, "target_cents": None},
        {"key": "carte",        "initial_cents": CARTE_INITIAL,     "attack_order": 2, "is_savings": False, "target_cents": None},
        {"key": "fonds_voyage", "initial_cents": 0, "attack_order": None, "is_savings": True,
         "target_cents": FUND_TARGET, "deadline_date": "2026-09-12"},
    ]
    proj = bp.compute(date(2026, 7, 11), [], debts_with_deadline, [])
    assert proj["fund_deadline"] == "2026-09-12"
    assert isinstance(proj["fund_at_deadline"], int)
    assert 0 <= proj["fund_at_deadline"] <= FUND_TARGET


# ── Windfall — balance oui, rythme non ─────────────────────────────────────

def test_paid_by_debt_includes_windfall():
    """Windfall compte dans paid_by_debt (réduit la balance)."""
    logs = [
        {"date": "2026-07-16", "type": "debt_payment", "debt_key": "decouvert", "amount_cents": 5000},
        {"date": "2026-07-17", "type": "windfall",     "debt_key": "decouvert", "amount_cents": 8000},
    ]
    assert bp._paid_by_debt(logs) == {"decouvert": 13000}


def test_measured_rates_excludes_windfall():
    """≥2 périodes complètes, uniquement des windfalls → rate mesuré = 0
    (protection anti-yo-yo : le one-shot ne doit pas gonfler la projection)."""
    logs = [
        {"date": "2026-07-20", "type": "windfall", "debt_key": "decouvert", "amount_cents": 50000},
        {"date": "2026-08-05", "type": "windfall", "debt_key": "decouvert", "amount_cents": 30000},
    ]
    proj = bp.compute(date(2026, 8, 15), [], DEBTS, logs)
    assert proj["projection"]["is_fallback_rate"] is False
    assert proj["projection"]["attack_rate_cents_per_day"] == 0
    assert proj["projection"]["fund_rate_cents_per_day"] == 0


def test_windfall_advances_death_via_balance_only():
    """À rate mesuré identique, un windfall raccourcit la mort par baisse du solde,
    pas par accélération du rythme. Prouve que balance et rate sont découplés."""
    debt_payment_logs = [
        {"date": "2026-07-20", "type": "debt_payment", "debt_key": "decouvert", "amount_cents": 30000},
    ]
    mixed_logs = debt_payment_logs + [
        {"date": "2026-08-05", "type": "windfall", "debt_key": "decouvert", "amount_cents": 40000},
    ]
    proj_a = bp.compute(date(2026, 8, 15), [], DEBTS, debt_payment_logs)
    proj_b = bp.compute(date(2026, 8, 15), [], DEBTS, mixed_logs)
    # Même rythme mesuré (windfall exclu du calcul).
    assert proj_a["projection"]["attack_rate_cents_per_day"] == proj_b["projection"]["attack_rate_cents_per_day"]
    # Mais la mort avance (balance réduite par le windfall).
    assert proj_b["death_dates"]["decouvert"] < proj_a["death_dates"]["decouvert"]


# ── Payload shape ───────────────────────────────────────────────────────────

def test_compute_payload_shape():
    """Contrat de sortie : clés attendues, types corrects."""
    proj = bp.compute(date(2026, 7, 11), [], DEBTS, [])
    assert set(proj.keys()) == {"paid_by_debt", "projection", "death_dates",
                                 "fund_completion", "fund_deadline", "fund_at_deadline",
                                 "next_milestone"}
    p = proj["projection"]
    assert set(p.keys()) == {"attack_rate_cents_per_day", "fund_rate_cents_per_day", "is_fallback_rate"}
    assert isinstance(p["attack_rate_cents_per_day"], int)
    assert isinstance(p["fund_rate_cents_per_day"], int)
    assert isinstance(p["is_fallback_rate"], bool)
    # death_dates : String ISO ou None
    for v in proj["death_dates"].values():
        assert v is None or (isinstance(v, str) and len(v) == 10)
    # next_milestone : structure ou None
    m = proj["next_milestone"]
    if m is not None:
        assert set(m.keys()) == {"kind", "key", "threshold_cents", "projected_date", "days_remaining"}
        assert m["kind"] in ("debt_threshold", "debt_death", "fund_quarter", "fund_complete")
