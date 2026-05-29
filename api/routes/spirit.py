"""routes/spirit.py — Spirit Pillar: breathwork, meditation, journaling.
Journal content is ultra-private — never included in AI coach context or exports.
"""
from __future__ import annotations
from flask import Blueprint, jsonify, request
from datetime import date
import logging
from utils import _today_mtl

logger = logging.getLogger("trainingos.spirit")
spirit_bp = Blueprint("spirit", __name__)


# ── Config ────────────────────────────────────────────────────────────────────

@spirit_bp.route("/api/spirit/config", methods=["GET"])
def api_spirit_config_get():
    import db
    return jsonify(db.get_spirit_config() or {})


@spirit_bp.route("/api/spirit/config", methods=["POST"])
def api_spirit_config_update():
    import db
    data    = request.get_json(silent=True) or {}
    allowed = {"integration_phoenix"}
    payload = {k: v for k, v in data.items() if k in allowed}
    if not payload:
        return jsonify({"error": "No valid fields"}), 400
    ok = db.upsert_spirit_config(payload)
    if not ok:
        return jsonify({"error": "Erreur base de données"}), 500
    return jsonify({"ok": True})


# ── Breathwork ────────────────────────────────────────────────────────────────

@spirit_bp.route("/api/spirit/breathwork", methods=["GET"])
def api_spirit_breathwork_get():
    import db
    limit  = int(request.args.get("limit", 60))
    return jsonify(db.get_breathwork_sessions_spirit_alias(limit=limit) or [])


# WARNING: This route writes to breathwork_sessions.protocol (text) + Spirit columns (duration_sec, cycles, etc.).
# The wellness equivalent /api/breathwork/log writes to breathwork_sessions.technique (integer FK, legacy).
# Do NOT merge these two routes without a full schema analysis — they target different columns.
@spirit_bp.route("/api/spirit/breathwork", methods=["POST"])
def api_spirit_breathwork_log():
    import db
    data = request.get_json(silent=True) or {}

    protocol = data.get("protocol", "")
    if protocol not in ("calm_storm", "ignite", "stillness"):
        return jsonify({"error": "Invalid protocol"}), 400

    triggered_from = data.get("triggered_from", "standalone")
    if triggered_from not in ("standalone", "arsenal", "ritual", "morning"):
        triggered_from = "standalone"

    payload = {
        "protocol":       protocol,
        "date":           _today_mtl(),
        "duration_sec":   max(0, int(data.get("duration_sec", 0))),
        "cycles":         max(0, int(data.get("cycles", 0))),
        "triggered_from": triggered_from,
    }
    row = db.log_breathwork_session(payload)
    if not row:
        return jsonify({"error": "Erreur base de données"}), 500
    return jsonify({"ok": True, "id": row.get("id")}), 201


# ── Meditation ────────────────────────────────────────────────────────────────

@spirit_bp.route("/api/spirit/meditation", methods=["GET"])
def api_spirit_meditation_get():
    import db
    limit = int(request.args.get("limit", 60))
    return jsonify(db.get_meditation_sessions(limit=limit) or [])


@spirit_bp.route("/api/spirit/meditation", methods=["POST"])
def api_spirit_meditation_log():
    import db
    data = request.get_json(silent=True) or {}

    payload = {
        "planned_sec":   max(0, int(data.get("planned_sec",  0))),
        "actual_sec":    max(0, int(data.get("actual_sec",   0))),
        "bell_interval": max(0, int(data.get("bell_interval", 0))),
        "completed":     bool(data.get("completed", False)),
    }
    row = db.log_meditation_session(payload)
    if not row:
        return jsonify({"error": "Erreur base de données"}), 500
    return jsonify({"ok": True, "id": row.get("id")}), 201


# ── Journal ───────────────────────────────────────────────────────────────────

@spirit_bp.route("/api/spirit/journal", methods=["GET"])
def api_spirit_journal_list():
    import db
    limit   = int(request.args.get("limit", 30))
    entries = db.get_spirit_journal_entries(limit=limit) or []
    # Strip content — list endpoint returns only dates for privacy
    return jsonify([{"date": e["date"], "id": e["id"]} for e in entries])


@spirit_bp.route("/api/spirit/journal/<entry_date>", methods=["GET"])
def api_spirit_journal_entry(entry_date: str):
    import db
    entry = db.get_spirit_journal_entry(entry_date)
    if not entry:
        return jsonify({}), 200
    return jsonify(entry)


@spirit_bp.route("/api/spirit/journal", methods=["POST"])
def api_spirit_journal_save():
    import db
    data = request.get_json(silent=True) or {}
    payload = {
        "date":         data.get("date") or _today_mtl(),
        "grateful_for": (data.get("grateful_for") or "").strip()[:80] or None,
        "conquered":    (data.get("conquered")    or "").strip()[:80] or None,
        "haunting":     (data.get("haunting")     or "").strip()[:80] or None,
    }
    ok = db.save_spirit_journal_entry(payload)
    if not ok:
        return jsonify({"error": "Erreur base de données"}), 500
    return jsonify({"ok": True})


# ── Patterns ──────────────────────────────────────────────────────────────────

@spirit_bp.route("/api/spirit/patterns", methods=["GET"])
def api_spirit_patterns():
    import spirit_engine as _e
    return jsonify(_e.compute_spirit_patterns())
