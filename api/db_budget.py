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
                .select("key, label, initial_cents, interest_rate, attack_order, is_savings, target_cents, deadline_date")
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
    """Insert générique d'un money_log (expense/debt_payment/fund_transfer/windfall).
    Le pairage type↔clé est validé côté route AVANT l'appel."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False
    payload = {
        "date":         entry["date"],
        "type":         entry["type"],
        "amount_cents": int(entry["amount_cents"]),
        "envelope_key": entry.get("envelope_key"),
        "debt_key":     entry.get("debt_key"),
        "category_key": entry.get("category_key"),
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


def list_money_logs_by_month(year_month: str) -> list:
    """[{id, date, type, amount_cents, envelope_key, debt_key, category_key, note}]
    pour un mois YYYY-MM. Order date DESC, id DESC. TOUS types (income + expense +
    debt_payment + fund_transfer + windfall), positifs ET négatifs (contre-écritures
    incluses — contrairement à today_transfers filtré > 0). Registre Diff C."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []
    y, m = year_month.split("-")
    y_i, m_i = int(y), int(m)
    start = f"{y_i:04d}-{m_i:02d}-01"
    if m_i == 12:
        next_y, next_m = y_i + 1, 1
    else:
        next_y, next_m = y_i, m_i + 1
    end = f"{next_y:04d}-{next_m:02d}-01"  # borne exclusive
    def _do() -> list:
        resp = (db_core._client.table("money_logs")
                .select("id, date, type, amount_cents, envelope_key, debt_key, category_key, note")
                .gte("date", start)
                .lt("date", end)
                .order("date", desc=True)
                .order("id", desc=True)
                .execute())
        return resp.data or []
    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try: return _do()
            except Exception as e2:
                db_core.logger.error("list_money_logs_by_month retry error: %s", e2)
                return []
        db_core.logger.error("list_money_logs_by_month error: %s", e)
        return []


def list_debt_and_fund_logs_since(start_iso: str) -> list:
    """[{date, type, debt_key, envelope_key, amount_cents}] pour expense +
    debt_payment + fund_transfer + windfall depuis start_iso. Alimente
    budget_projection (rythme et paid_by_debt ignorent expense via filtres de
    type et absence de debt_key) et today_transfers (broader filter dans
    budget.py — expense inclus pour cocher hypothèque et alimenter le solde live)."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []
    def _do() -> list:
        resp = (db_core._client.table("money_logs")
                .select("date, type, debt_key, envelope_key, category_key, amount_cents")
                .in_("type", ["expense", "debt_payment", "fund_transfer", "windfall"])
                .gte("date", start_iso)
                .execute())
        return resp.data or []
    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try: return _do()
            except Exception as e2:
                db_core.logger.error("list_debt_and_fund_logs_since retry error: %s", e2)
                return []
        db_core.logger.error("list_debt_and_fund_logs_since error: %s", e)
        return []
