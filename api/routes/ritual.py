"""Routes — Daily Engagements (cycle créer/adresser)."""
from __future__ import annotations
from flask import Blueprint, jsonify, request
from datetime import date, timedelta, datetime, timezone
import logging
from utils import _today_mtl_date as _today_mtl

logger = logging.getLogger("trainingos.ritual")
ritual_bp = Blueprint("ritual", __name__)


# ── Engagement streak (jours consécutifs avec ≥1 engagement tenu) ────────────

def _engagement_streak(max_days: int = 90) -> int:
    """Compte les jours consécutifs avec ≥1 engagement status='done' en remontant depuis HIER.

    - Aujourd'hui exclu (engagements pas encore forcément tenus).
    - Jour SANS engagement inscrit = neutre, ne casse pas le streak.
    - Jour AVEC engagements mais 0 tenu = rupture.
    """
    import db as _db
    today    = _today_mtl()
    end      = today - timedelta(days=1)              # hier inclus
    start    = today - timedelta(days=max_days)
    rows     = _db.get_engagements_since(start.isoformat(), end.isoformat())

    by_date: dict[str, list[dict]] = {}
    for r in rows:
        by_date.setdefault(r["date"], []).append(r)

    streak = 0
    cursor = end
    for _ in range(max_days):
        key = cursor.isoformat()
        if key in by_date:
            if any(e.get("status") == "done" for e in by_date[key]):
                streak += 1
            else:
                break
        # sinon : jour sans engagement inscrit, neutre
        cursor -= timedelta(days=1)
    return streak


# ── Routes ───────────────────────────────────────────────────────────────────

@ritual_bp.route("/api/ritual/today")
def api_ritual_today():
    import db as _db

    today_str            = _today_mtl().isoformat()
    tomorrow_str         = (_today_mtl() + timedelta(days=1)).isoformat()
    engagements          = _db.get_engagements_for_date(today_str)
    tomorrow_engagements = _db.get_engagements_for_date(tomorrow_str)

    return jsonify({
        "date":                 today_str,
        "engagements":          engagements,
        "tomorrow_engagements": tomorrow_engagements,
    })


@ritual_bp.route("/api/ritual/engagements", methods=["GET"])
def api_ritual_engagements_get():
    """Return engagements for a given date (default = today)."""
    import db as _db
    date_str = request.args.get("date") or _today_mtl().isoformat()
    rows = _db.get_engagements_for_date(date_str)
    return jsonify(rows)


@ritual_bp.route("/api/ritual/engagements", methods=["POST"])
def api_ritual_engagements_create():
    """Replace all engagements for a date. Body: {date, engagements: [str]}."""
    import db as _db
    data     = request.get_json(silent=True) or {}
    date_str = (data.get("date") or "").strip()
    texts    = [t for t in (data.get("engagements") or []) if isinstance(t, str) and t.strip()]
    if not date_str:
        return jsonify({"error": "date is required"}), 400
    if not texts:
        return jsonify({"error": "at least one engagement is required"}), 400
    if len(texts) > 5:
        return jsonify({"error": "maximum 5 engagements per day"}), 400
    rows = _db.create_engagements(date_str, texts)
    from routes.daily_brief import invalidate_cache as _brief_invalidate
    _brief_invalidate()
    return jsonify({"ok": True, "engagements": rows})


@ritual_bp.route("/api/ritual/engagements/<engagement_id>", methods=["PATCH"])
def api_ritual_engagements_update(engagement_id: str):
    """Update the status of a single engagement. Body: {status: 'done'|'notdone'}."""
    import db as _db
    data   = request.get_json(silent=True) or {}
    status = (data.get("status") or "").strip()
    if status not in ("done", "notdone"):
        return jsonify({"error": "status must be 'done' or 'notdone'"}), 400
    ok = _db.update_engagement_status(engagement_id, status)
    if not ok:
        return jsonify({"error": "Erreur base de données"}), 500
    return jsonify({"ok": True})
