"""Tests purs (pas de DB) : logique de période paie."""
from datetime import date

import budget as b


def test_paydays_february_2026():
    assert b._paydays_for_month(2026, 2) == (date(2026, 2, 15), date(2026, 2, 28))


def test_paydays_march():
    assert b._paydays_for_month(2026, 3) == (date(2026, 3, 15), date(2026, 3, 30))


def test_paydays_january():
    assert b._paydays_for_month(2027, 1) == (date(2027, 1, 15), date(2027, 1, 30))


def test_current_period_start_before_15():
    assert b.current_period_start(date(2027, 1, 14)) == date(2026, 12, 30)


def test_current_period_start_on_15():
    assert b.current_period_start(date(2027, 1, 15)) == date(2027, 1, 15)


def test_current_period_start_between():
    assert b.current_period_start(date(2027, 1, 29)) == date(2027, 1, 15)


def test_current_period_start_on_30():
    assert b.current_period_start(date(2027, 1, 30)) == date(2027, 1, 30)


def test_current_period_start_on_31():
    assert b.current_period_start(date(2027, 1, 31)) == date(2027, 1, 30)


def test_current_period_start_feb_28():
    assert b.current_period_start(date(2026, 2, 28)) == date(2026, 2, 28)


def test_current_period_start_march_1():
    assert b.current_period_start(date(2026, 3, 1)) == date(2026, 2, 28)


def test_next_payday_before_15():
    assert b.next_payday(date(2027, 1, 14)) == date(2027, 1, 15)


def test_next_payday_on_15():
    assert b.next_payday(date(2027, 1, 15)) == date(2027, 1, 30)


def test_next_payday_between():
    assert b.next_payday(date(2027, 1, 29)) == date(2027, 1, 30)


def test_next_payday_on_30():
    assert b.next_payday(date(2027, 1, 30)) == date(2027, 2, 15)


def test_next_payday_feb_28():
    assert b.next_payday(date(2026, 2, 28)) == date(2026, 3, 15)


def test_next_payday_year_wrap():
    assert b.next_payday(date(2026, 12, 30)) == date(2027, 1, 15)
