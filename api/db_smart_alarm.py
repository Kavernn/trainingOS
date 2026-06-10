from __future__ import annotations
from typing import Optional
import db_core


def _latency_min(tap: str, hk: str) -> Optional[float]:
    """Minutes between bedtime_tap and hk_sleep_start. Handles midnight crossing."""
    try:
        def to_min(t: str) -> int:
            h, m = map(int, t.split(":"))
            return h * 60 + m
        diff = to_min(hk) - to_min(tap)
        if diff < 0:
            diff += 24 * 60
        return float(diff)
    except Exception:
        return None


def upsert_smart_alarm_session(data: dict) -> bool:
    """Insert or update a smart_alarm_sessions row by date."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = (
            db_core._client.table("smart_alarm_sessions")
            .upsert(data, on_conflict="date")
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("upsert_smart_alarm_session retry: %s", e2)
                return False
        db_core.logger.error("upsert_smart_alarm_session error: %s", e)
        return False


def get_smart_alarm_sessions(since: str) -> list[dict]:
    """Return sessions with latency_min >= since date, sorted ascending."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> list[dict]:
        resp = (
            db_core._client.table("smart_alarm_sessions")
            .select("date, bedtime_tap, hk_sleep_start, latency_min")
            .gte("date", since)
            .order("date")
            .execute()
        )
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_smart_alarm_sessions retry: %s", e2)
                return []
        db_core.logger.error("get_smart_alarm_sessions error: %s", e)
        return []
