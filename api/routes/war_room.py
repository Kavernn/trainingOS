"""routes/war_room.py — The War Room: private combat tracker endpoints.
Ultra-private: never included in dashboards, exports, or analytics.
"""
from __future__ import annotations
from flask import Blueprint, jsonify, request
from datetime import date
import logging
from utils import _today_mtl

logger = logging.getLogger("trainingos.war_room")
war_room_bp = Blueprint("war_room", __name__)


# ── Config ───────────────────────────────────────────────────────────────────

@war_room_bp.route("/api/war_room/config", methods=["GET"])
def api_wr_config_get():
    import db
    config = db.get_war_room_config() or {}
    return jsonify(config)


@war_room_bp.route("/api/war_room/config", methods=["POST"])
def api_wr_config_update():
    import db
    data = request.get_json(silent=True) or {}
    allowed = {"war_start_date", "substance_label", "integration_phoenix",
               "integration_readiness", "integration_ai_coach"}
    payload = {k: v for k, v in data.items() if k in allowed}
    if not payload:
        return jsonify({"error": "No valid fields"}), 400
    ok = db.upsert_war_room_config(payload)
    if not ok:
        return jsonify({"error": "Erreur base de données"}), 500
    return jsonify({"ok": True})


# ── Summary ───────────────────────────────────────────────────────────────────

@war_room_bp.route("/api/war_room/summary", methods=["GET"])
def api_wr_summary():
    import war_room_engine as _e
    return jsonify(_e.compute_summary())


# ── Today status ──────────────────────────────────────────────────────────────

@war_room_bp.route("/api/war_room/today_status", methods=["GET"])
def api_wr_today_status():
    import db
    config = db.get_war_room_config() or {}
    if not config.get("war_start_date"):
        return jsonify({"active": False})
    today  = _today_mtl()
    status = db.get_war_room_today_status(today)
    return jsonify({"active": True, **status})


# ── Battles ───────────────────────────────────────────────────────────────────

@war_room_bp.route("/api/war_room/battles", methods=["GET"])
def api_wr_battles():
    import db
    limit = int(request.args.get("limit", 90))
    return jsonify(db.get_war_room_battles(limit=limit) or [])


@war_room_bp.route("/api/war_room/progress", methods=["GET"])
def api_wr_progress():
    """Read-only history of the existing single-user journal, with honest coverage.

    Keyset pagination avoids Supabase's implicit row cap. Never convert a DB
    failure into zero victories. No config-based filtering of historical results.
    """
    import db_core
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return jsonify({"error": "Historique indisponible"}), 503
    try:
        config = (db_core._client.table("war_room_config")
                  .select("war_start_date, updated_at").eq("id", 1).limit(1).execute()).data or []
        config = config[0] if config else {}
        today = _today_mtl()
        rows = []
        cursor = None
        complete = False
        # A bounded response remains explicitly partial if this safety cap is hit.
        for _ in range(20):
            query = (db_core._client.table("war_room_battles")
                     .select("id, date, status, notes, created_at, updated_at", count="exact")
                     .lte("date", today).order("date", desc=True).limit(500))
            if cursor:
                query = query.lt("date", cursor)
            page = query.execute()
            batch = page.data
            if batch is None or page.count is None:
                raise ValueError("Couverture de l'historique inconnue")
            rows.extend(batch)
            if len(batch) == page.count:
                complete = True
                break
            if not batch:
                raise ValueError("Page d'historique incomplète")
            cursor = batch[-1]["date"]
        latest = (db_core._client.table("war_room_config")
                  .select("war_start_date, updated_at").eq("id", 1).limit(1).execute()).data or []
        if (latest[0] if latest else {}) != config:
            return jsonify({"error": "Configuration modifiée, réessaie"}), 409
        return jsonify({"battles": rows, "complete": complete,
                        "start_date": config.get("war_start_date"),
                        "context": str(config.get("updated_at") or "personal"),
                        "through_date": today})
    except Exception:
        logger.exception("War Room history unavailable")
        return jsonify({"error": "Historique indisponible, réessaie"}), 503


@war_room_bp.route("/api/war_room/battle", methods=["POST"])
def api_wr_battle_upsert():
    import db
    data   = request.get_json(silent=True) or {}
    status = data.get("status", "")
    if status not in ("victory", "lost", "active"):
        return jsonify({"error": "status must be victory | lost | active"}), 400

    battle_date  = data.get("date") or _today_mtl()
    today_status = db.get_war_room_today_status(battle_date)
    if today_status.get("has_result") and not data.get("force"):
        return jsonify({
            "error":     "already_logged",
            "message":   "Résultat déjà loggué aujourd'hui",
            "logged_at": today_status.get("result_logged_at"),
        }), 409

    payload = {
        "date":   battle_date,
        "status": status,
        "notes":  (data.get("notes") or "").strip() or None,
    }
    ok = db.upsert_war_room_battle(payload)
    if not ok:
        return jsonify({"error": "Erreur base de données"}), 500

    # Auto-set war_start_date on first ever victory
    config = db.get_war_room_config() or {}
    if status == "victory" and not config.get("war_start_date"):
        db.upsert_war_room_config({"war_start_date": battle_date})

    import war_room_engine as _e
    return jsonify({"ok": True, "summary": _e.compute_summary()})


# ── Trigger log ───────────────────────────────────────────────────────────────

@war_room_bp.route("/api/war_room/triggers", methods=["GET"])
def api_wr_triggers():
    import db
    limit = int(request.args.get("limit", 90))
    return jsonify(db.get_war_room_triggers(limit=limit) or [])


@war_room_bp.route("/api/war_room/trigger", methods=["POST"])
def api_wr_trigger_log():
    import db
    data         = request.get_json(silent=True) or {}
    trigger_date = data.get("date") or _today_mtl()
    today_status = db.get_war_room_today_status(trigger_date)
    if today_status.get("has_temptation"):
        return jsonify({
            "error":     "already_logged",
            "message":   "Tentation déjà loggée aujourd'hui",
            "logged_at": today_status.get("temptation_logged_at"),
        }), 409

    context = data.get("context", "custom")
    valid_contexts = {"stress", "social", "boredom", "pain", "celebration", "exhaustion", "custom"}
    if context not in valid_contexts:
        context = "custom"

    intensity = int(data.get("intensity", 3))
    intensity = max(1, min(5, intensity))
    yielded   = bool(data.get("yielded", False))

    payload = {
        "date":         trigger_date,
        "context":      context,
        "context_note": (data.get("context_note") or "").strip() or None,
        "intensity":    intensity,
        "yielded":      yielded,
        "held_with":    data.get("held_with") or [],
    }
    row = db.insert_war_room_trigger(payload)
    if not row:
        return jsonify({"error": "Erreur base de données"}), 500
    return jsonify({"ok": True, "id": row.get("id")})


# ── Arsenal ───────────────────────────────────────────────────────────────────

@war_room_bp.route("/api/war_room/arsenal", methods=["GET"])
def api_wr_arsenal():
    import db
    items = db.get_war_room_arsenal() or []
    return jsonify(sorted(items, key=lambda x: (-x.get("use_count", 0), x.get("sort_order", 0))))


@war_room_bp.route("/api/war_room/arsenal", methods=["POST"])
def api_wr_arsenal_add():
    import db
    data  = request.get_json(silent=True) or {}
    label = (data.get("label") or "").strip()
    if not label:
        return jsonify({"error": "label is required"}), 400

    valid_cats = {"call", "physical", "breath", "mental", "environment", "other"}
    category   = data.get("category", "other")
    if category not in valid_cats:
        category = "other"

    payload = {
        "label":      label,
        "category":   category,
        "sort_order": int(data.get("sort_order", 0)),
    }
    row = db.insert_war_room_arsenal_item(payload)
    if not row:
        return jsonify({"error": "Erreur base de données"}), 500
    return jsonify({"ok": True, "id": row.get("id")}), 201


@war_room_bp.route("/api/war_room/arsenal/<item_id>", methods=["DELETE"])
def api_wr_arsenal_delete(item_id: str):
    import db
    ok = db.delete_war_room_arsenal_item(item_id)
    if not ok:
        return jsonify({"error": "Not found or error"}), 404
    return jsonify({"ok": True})


@war_room_bp.route("/api/war_room/arsenal/<item_id>/deploy", methods=["POST"])
def api_wr_arsenal_deploy(item_id: str):
    import db
    ok = db.increment_arsenal_use(item_id)
    if not ok:
        return jsonify({"error": "Not found"}), 404
    return jsonify({"ok": True})


# ── Patterns ──────────────────────────────────────────────────────────────────

@war_room_bp.route("/api/war_room/patterns", methods=["GET"])
def api_wr_patterns():
    import war_room_engine as _e
    return jsonify(_e.compute_patterns())


# ── War map (calendar data) ────────────────────────────────────────────────────

@war_room_bp.route("/api/war_room/map", methods=["GET"])
def api_wr_map():
    import db
    battles = db.get_war_room_battles(limit=365) or []
    # Group by month
    months: dict[str, dict] = {}
    for b in battles:
        d   = b.get("date", "")
        key = d[:7] if len(d) >= 7 else ""
        if not key:
            continue
        if key not in months:
            months[key] = {"month": key, "days": []}
        months[key]["days"].append({"date": d, "status": b.get("status")})
    result = sorted(months.values(), key=lambda m: m["month"])
    return jsonify(result)
