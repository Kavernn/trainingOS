"""Budget — helpers Supabase pour budget_envelopes, debt_accounts, money_logs.

Pattern strict api/db_body.py : _do() interne, retry sur disconnect,
log + fallback silencieux. SELECT colonnes explicites (jamais SELECT *).
"""
from __future__ import annotations
import db_core


def get_envelopes() -> list:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []
    def _do() -> list:
        resp = (db_core._client.table("budget_envelopes")
                .select("key, label, limit_cents")
                .order("key")
                .execute())
        return resp.data or []
    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try: return _do()
            except Exception as e2:
                db_core.logger.error("get_envelopes retry error: %s", e2)
                return []
        db_core.logger.error("get_envelopes error: %s", e)
        return []


def get_debt_accounts() -> list:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []
    def _do() -> list:
        resp = (db_core._client.table("debt_accounts")
                .select("key, label, initial_cents, interest_rate, attack_order, is_savings, target_cents")
                .order("attack_order", desc=False, nullsfirst=False)
                .execute())
        return resp.data or []
    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try: return _do()
            except Exception as e2:
                db_core.logger.error("get_debt_accounts retry error: %s", e2)
                return []
        db_core.logger.error("get_debt_accounts error: %s", e)
        return []


def get_last_income_date() -> str | None:
    """ISO date de la dernière paie loggée, ou None si aucune."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None
    def _do() -> str | None:
        resp = (db_core._client.table("money_logs")
                .select("date")
                .eq("type", "income")
                .order("date", desc=True)
                .limit(1)
                .execute())
        rows = resp.data or []
        return rows[0]["date"] if rows else None
    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try: return _do()
            except Exception as e2:
                db_core.logger.error("get_last_income_date retry error: %s", e2)
                return None
        db_core.logger.error("get_last_income_date error: %s", e)
        return None


def insert_income_if_absent(date_iso: str, amount_cents: int) -> bool:
    """Insère une paie si absente pour ce (date, type='income').

    Non-atomique (SELECT-then-INSERT) ; ux_money_logs_income_date est
    la garantie finale d'idempotence — une course lèverait une unique
    violation captée ci-dessous, comportement correct (return False).
    Retourne True si insertion effective, False sinon (déjà présente / erreur).
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False
    def _do() -> bool:
        exists = (db_core._client.table("money_logs")
                  .select("id")
                  .eq("date", date_iso).eq("type", "income")
                  .limit(1).execute())
        if exists.data:
            return False
        resp = (db_core._client.table("money_logs")
                .insert({"date": date_iso, "type": "income", "amount_cents": amount_cents})
                .execute())
        return bool(resp.data)
    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try: return _do()
            except Exception as e2:
                db_core.logger.error("insert_income_if_absent retry error: %s", e2)
                return False
        db_core.logger.error("insert_income_if_absent error: %s", e)
        return False


def insert_log(entry: dict) -> bool:
    """Insert générique d'un money_log (expense/debt_payment/fund_transfer).
    Le pairage type↔clé est validé côté route AVANT l'appel."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False
    payload = {
        "date":         entry["date"],
        "type":         entry["type"],
        "amount_cents": int(entry["amount_cents"]),
        "envelope_key": entry.get("envelope_key"),
        "debt_key":     entry.get("debt_key"),
        "note":         entry.get("note"),
    }
    def _do() -> bool:
        resp = db_core._client.table("money_logs").insert(payload).execute()
        return bool(resp.data)
    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try: return _do()
            except Exception as e2:
                db_core.logger.error("insert_log retry error: %s", e2)
                return False
        db_core.logger.error("insert_log error: %s", e)
        return False


def sum_expenses_by_envelope(start_iso: str, end_iso: str) -> dict:
    """{envelope_key: sum_cents} pour type='expense' dans [start, end]."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return {}
    def _do() -> dict:
        resp = (db_core._client.table("money_logs")
                .select("envelope_key, amount_cents")
                .eq("type", "expense")
                .gte("date", start_iso).lte("date", end_iso)
                .execute())
        totals: dict = {}
        for row in (resp.data or []):
            k = row.get("envelope_key")
            if not k: continue
            totals[k] = totals.get(k, 0) + int(row.get("amount_cents") or 0)
        return totals
    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try: return _do()
            except Exception as e2:
                db_core.logger.error("sum_expenses_by_envelope retry error: %s", e2)
                return {}
        db_core.logger.error("sum_expenses_by_envelope error: %s", e)
        return {}


def sum_debt_payments(debt_key: str) -> int:
    """SUM(amount_cents) pour debt_key donné, types debt_payment + fund_transfer.
    fund_transfer inclus car alimente les fonds d'épargne (fonds_voyage)."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return 0
    def _do() -> int:
        resp = (db_core._client.table("money_logs")
                .select("amount_cents")
                .eq("debt_key", debt_key)
                .in_("type", ["debt_payment", "fund_transfer"])
                .execute())
        return sum(int(r.get("amount_cents") or 0) for r in (resp.data or []))
    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try: return _do()
            except Exception as e2:
                db_core.logger.error("sum_debt_payments retry error: %s", e2)
                return 0
        db_core.logger.error("sum_debt_payments error: %s", e)
        return 0
