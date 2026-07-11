"""Tests purs (pas de DB) : logique de période paie.

Règle weekend : quand une paie (15 ou min(30, dernier jour)) tombe un samedi
ou dimanche, elle est AVANCÉE au vendredi précédent. Jamais reculée.
Fériés exclus (différé au carnet de ménage).
"""
from datetime import date

import budget as b


# ── _adjust_for_weekend : test direct des 3 branches ────────────────────────

def test_adjust_saturday_to_friday():
    # 2026-08-15 = samedi
    assert b._adjust_for_weekend(date(2026, 8, 15)) == date(2026, 8, 14)


def test_adjust_sunday_to_friday():
    # 2026-08-30 = dimanche
    assert b._adjust_for_weekend(date(2026, 8, 30)) == date(2026, 8, 28)


def test_adjust_weekday_unchanged():
    # 2026-07-15 = mercredi
    assert b._adjust_for_weekend(date(2026, 7, 15)) == date(2026, 7, 15)


# ── _paydays_for_month ──────────────────────────────────────────────────────

def test_paydays_february_2026():
    # 15 fev 2026 = dimanche → 13 ; 28 fev 2026 = samedi → 27
    assert b._paydays_for_month(2026, 2) == (date(2026, 2, 13), date(2026, 2, 27))


def test_paydays_march_2026():
    # 15 mars 2026 = dimanche → 13 ; 30 mars 2026 = lundi, inchangé
    assert b._paydays_for_month(2026, 3) == (date(2026, 3, 13), date(2026, 3, 30))


def test_paydays_january_2027():
    # 15 janv 2027 = vendredi ; 30 janv 2027 = samedi → 29
    assert b._paydays_for_month(2027, 1) == (date(2027, 1, 15), date(2027, 1, 29))


def test_paydays_july_2026_sentinel():
    # Sentinelle : mois sans aucune collision weekend.
    # 15 juil 2026 = mercredi, 30 juil 2026 = jeudi.
    assert b._paydays_for_month(2026, 7) == (date(2026, 7, 15), date(2026, 7, 30))


def test_paydays_august_2026_both_shifted():
    # 15 août 2026 = samedi → 14 ; 30 août 2026 = dimanche → 28.
    assert b._paydays_for_month(2026, 8) == (date(2026, 8, 14), date(2026, 8, 28))


def test_paydays_november_2026_p1_shifted():
    # 15 nov 2026 = dimanche → 13 ; 30 nov 2026 = lundi, inchangé.
    assert b._paydays_for_month(2026, 11) == (date(2026, 11, 13), date(2026, 11, 30))


# ── current_period_start ────────────────────────────────────────────────────

def test_current_period_start_before_15():
    # 14 janv 2027 → prev = déc 2026, p2 déc 2026 = 30 (mercredi, OK)
    assert b.current_period_start(date(2027, 1, 14)) == date(2026, 12, 30)


def test_current_period_start_on_15():
    # 15 janv 2027 = vendredi, p1 inchangé
    assert b.current_period_start(date(2027, 1, 15)) == date(2027, 1, 15)


def test_current_period_start_between_29_jan_2027():
    # 29 janv 2027 = vendredi, p2 ajusté = 29 → today >= p2
    assert b.current_period_start(date(2027, 1, 29)) == date(2027, 1, 29)


def test_current_period_start_on_30_jan_2027():
    # 30 janv 2027 = samedi, p2 ajusté = 29
    assert b.current_period_start(date(2027, 1, 30)) == date(2027, 1, 29)


def test_current_period_start_on_31_jan_2027():
    # 31 janv 2027 = dimanche, p2 ajusté = 29
    assert b.current_period_start(date(2027, 1, 31)) == date(2027, 1, 29)


def test_current_period_start_feb_28_2026():
    # 28 fev 2026 = samedi, p2 ajusté = 27
    assert b.current_period_start(date(2026, 2, 28)) == date(2026, 2, 27)


def test_current_period_start_march_1_2026():
    # 1 mars 2026 = dimanche, p1 mars ajusté = 13 → today < p1 → prev p2 fev = 27
    assert b.current_period_start(date(2026, 3, 1)) == date(2026, 2, 27)


def test_current_period_start_aug_30_2026():
    # 30 août 2026 = dimanche → appartient à la période commencée le vendredi 28.
    assert b.current_period_start(date(2026, 8, 30)) == date(2026, 8, 28)


# ── next_payday ─────────────────────────────────────────────────────────────

def test_next_payday_before_15():
    # 14 janv 2027 → p1 = 15 (vendredi)
    assert b.next_payday(date(2027, 1, 14)) == date(2027, 1, 15)


def test_next_payday_on_15_jan_2027():
    # 15 janv 2027 = vendredi ; p2 ajusté = 29
    assert b.next_payday(date(2027, 1, 15)) == date(2027, 1, 29)


def test_next_payday_between_29_jan_2027():
    # 29 janv 2027 = vendredi, p2=29 → fall-through → p1 fev 2027 = 15 (lundi)
    assert b.next_payday(date(2027, 1, 29)) == date(2027, 2, 15)


def test_next_payday_on_30_jan_2027():
    # 30 janv 2027 = samedi, p2 ajusté = 29 → fall-through → p1 fev 2027 = 15
    assert b.next_payday(date(2027, 1, 30)) == date(2027, 2, 15)


def test_next_payday_feb_28_2026():
    # 28 fev 2026 = samedi, p2 fev ajusté = 27 → fall-through → p1 mars = 13 (dim ajusté)
    assert b.next_payday(date(2026, 2, 28)) == date(2026, 3, 13)


def test_next_payday_year_wrap():
    # 30 déc 2026 = mercredi, p2 déc = 30 → fall-through → p1 janv 2027 = 15 (ven)
    assert b.next_payday(date(2026, 12, 30)) == date(2027, 1, 15)


def test_next_payday_aug_29_2026_reaches_september():
    # 29 août 2026 = samedi. p2 août ajusté = 28 (dim 30 → ven 28) → fall-through
    # → p1 sept 2026 = 15 (mardi, aucun ajustement).
    assert b.next_payday(date(2026, 8, 29)) == date(2026, 9, 15)


def test_next_payday_oct_30_2026_targets_november_friday():
    # Bug historique A2 : today = 30 oct 2026 (vendredi), p2 oct = 30 → fall-through.
    # 15 nov 2026 = dimanche → doit retourner vendredi 13, PAS le 15.
    assert b.next_payday(date(2026, 10, 30)) == date(2026, 11, 13)
