"""Routes — Daily Ritual ('Kill the old me / Let the new me rise')."""
from __future__ import annotations
from flask import Blueprint, jsonify, request
from datetime import date, timedelta, datetime, timezone
import random
import logging
from utils import _today_mtl_date as _today_mtl

logger = logging.getLogger("trainingos.ritual")
ritual_bp = Blueprint("ritual", __name__)


_DEFAULT_TRUTHS = [
    ("Tu joues la sécurité depuis trop longtemps.", "default"),
    ("La version de toi d'il y a 6 mois ne ferait pas mieux.", "default"),
    ("Chaque jour sans intention est une journée perdue.", "default"),
    ("Tu sais exactement ce que tu dois changer. Tu ne le fais pas.", "default"),
    ("Il n'y a pas de version facile de ce que tu veux devenir.", "default"),
    ("L'ancienne version de toi survit parce que tu la laisses faire.", "default"),
]


# ── Carry count computation from actual dates (A1) ──────────────────────────

def _enrich_carry_counts(demons: list[dict]) -> list[dict]:
    """Recompute carry_count from actual date difference — never trust stored value."""
    today = _today_mtl()
    enriched = []
    for d in demons:
        try:
            demon_date = date.fromisoformat(d["date"])
            actual_carry = (today - demon_date).days
            enriched.append({**d, "carry_count": actual_carry})
        except Exception:
            enriched.append(d)
    return enriched



# ── Phoenix streak computation ───────────────────────────────────────────────

def _compute_phoenix() -> tuple[int, int, int]:
    import db as _db
    rows = _db.get_ritual_history(limit=365)
    if not rows:
        return 0, 0, 0

    total_burned = sum(1 for r in rows if r.get("outcome") == "burned")

    completed = [r for r in rows if r.get("outcome") in ("burned", "survived")]
    current = 0
    for r in completed:
        if r.get("outcome") == "burned":
            current += 1
        else:
            break

    best, run = 0, 0
    for r in sorted(rows, key=lambda r: r.get("date", "")):
        if r.get("outcome") == "burned":
            run += 1
            best = max(best, run)
        elif r.get("outcome") == "survived":
            run = 0

    return current, best, total_burned


# ── Routes ───────────────────────────────────────────────────────────────────

@ritual_bp.route("/api/ritual/today")
def api_ritual_today():
    import db as _db

    today_str           = _today_mtl().isoformat()
    yesterday_str        = (_today_mtl() - timedelta(days=1)).isoformat()
    existing             = _db.get_ritual_today(today_str)
    yesterday_ritual     = _db.get_ritual_today(yesterday_str)
    yesterday_intention  = (yesterday_ritual or {}).get("tomorrow_intention")
    yesterday_outcome    = (yesterday_ritual or {}).get("outcome")
    yesterday_evening_at = (yesterday_ritual or {}).get("evening_at")
    streak, best, total = _compute_phoenix()
    raw_demons          = _db.get_ritual_demons()
    demons              = _enrich_carry_counts(raw_demons)  # A1

    if existing:
        # Surface oldest demon even on existing
        carried_intention = existing.get("carried_intention")
        carried_from      = existing.get("carried_from")
        carry_count       = existing.get("carry_count", 0)
        if not carried_intention:
            survived_demons = [d for d in demons if d.get("carry_count", 0) > 0]
            if survived_demons:
                oldest            = sorted(survived_demons, key=lambda d: d.get("date", ""))[0]
                carried_intention = oldest.get("intention")
                carried_from      = oldest.get("date")
                carry_count       = oldest.get("carry_count", 0)
        return jsonify({
            **existing,
            "carry_count":           carry_count,
            "carried_from":          carried_from,
            "carried_intention":     carried_intention,
            "phoenix_streak":        streak,
            "phoenix_best":          best,
            "phoenix_total_burned":  total,
            "demons":                demons,
            "yesterday_intention":   yesterday_intention,
            "yesterday_outcome":     yesterday_outcome,
            "yesterday_evening_at":  yesterday_evening_at,
        })

    truth, ttype = random.choice(_DEFAULT_TRUTHS)

    carried_intention = None
    carried_from      = None
    carry_count       = 0
    survived_demons   = [d for d in demons if d.get("carry_count", 0) > 0]
    if survived_demons:
        oldest            = sorted(survived_demons, key=lambda d: d.get("date", ""))[0]
        carried_intention = oldest.get("intention")
        carried_from      = oldest.get("date")
        carry_count       = oldest.get("carry_count", 0)

    try:
        _db.upsert_ritual({
            "date":         today_str,
            "truth":        truth,
            "truth_type":   ttype,
            "carry_count":  carry_count,
            "carried_from": carried_from,
        })
    except Exception:
        pass

    return jsonify({
        "date":                  today_str,
        "truth":                 truth,
        "truth_type":            ttype,
        "intention":             None,
        "morning_at":            None,
        "outcome":               None,
        "evening_at":            None,
        "carry_count":           carry_count,
        "carried_from":          carried_from,
        "carried_intention":     carried_intention,
        "phoenix_streak":        streak,
        "phoenix_best":          best,
        "phoenix_total_burned":  total,
        "demons":                demons,
        "yesterday_intention":       yesterday_intention,
        "yesterday_outcome":         yesterday_outcome,
        "yesterday_evening_at":      yesterday_evening_at,
        "morning_ack":               None,
        "routine_no_food":           False,
        "routine_dim_lights":        False,
        "routine_shower":            False,
        "routine_connection":        False,
        "routine_deconnect":         False,
        "routine_priorities_done":   False,
        "routine_bedtime_ok":        False,
        "routine_completed_at":      None,
    })


@ritual_bp.route("/api/ritual/morning", methods=["POST"])
def api_ritual_morning():
    import db as _db

    data      = request.get_json(silent=True) or {}
    intention = (data.get("intention") or "").strip()
    if not intention:
        return jsonify({"error": "intention is required"}), 400

    today_str = _today_mtl().isoformat()
    now_iso   = datetime.now(timezone.utc).isoformat()
    existing  = _db.get_ritual_today(today_str) or {}

    if existing.get("truth"):
        truth, ttype = existing["truth"], existing["truth_type"]
    else:
        truth, ttype = random.choice(_DEFAULT_TRUTHS)

    payload = {
        "date":         today_str,
        "truth":        truth,
        "truth_type":   ttype,
        "intention":    intention,
        "morning_at":   existing.get("morning_at") or now_iso,
        "carry_count":  int(data.get("carry_count", 0)),
        "carried_from": data.get("carried_from"),
    }
    ok = _db.upsert_ritual(payload)
    if not ok:
        return jsonify({"error": "Erreur base de données"}), 500
    return jsonify({"ok": True})


@ritual_bp.route("/api/ritual/evening", methods=["POST"])
def api_ritual_evening():
    import db as _db

    data    = request.get_json(silent=True) or {}
    outcome = data.get("outcome", "")
    if outcome not in ("burned", "survived"):
        return jsonify({"error": "outcome must be 'burned' or 'survived'"}), 400

    today_str = _today_mtl().isoformat()
    existing  = _db.get_ritual_today(today_str)
    if not existing or not existing.get("intention"):
        return jsonify({"error": "Complete the morning ritual first"}), 400

    now_iso              = datetime.now(timezone.utc).isoformat()
    reflection           = (data.get("reflection") or "").strip() or None
    winddown             = data.get("winddown_done")
    cold                 = data.get("cold_done")
    gratitude            = (data.get("gratitude") or "").strip() or None
    tomorrow_intention   = (data.get("tomorrow_intention") or "").strip() or None

    patch = {**existing, "outcome": outcome, "evening_at": now_iso}
    if reflection is not None:
        patch["reflection"] = reflection
    if winddown is not None:
        patch["winddown_done"] = bool(winddown)
    if cold is not None:
        patch["cold_done"] = bool(cold)
    if gratitude:
        patch["gratitude"] = gratitude
    if tomorrow_intention is not None:
        patch["tomorrow_intention"] = tomorrow_intention
        patch["routine_priorities_done"] = True

    ok = _db.upsert_ritual(patch)
    if not ok:
        return jsonify({"error": "Erreur base de données"}), 500

    streak, best, total = _compute_phoenix()

    # C9: detect if intention was honored via session data
    intention_matched_session = False
    try:
        sessions_today = [s for s in _db.get_workout_sessions(limit=5) if s.get("date") == today_str]
        if sessions_today and existing.get("intention"):
            intention_lower = existing["intention"].lower()
            workout_words = {"séance", "squat", "bench", "deadlift", "soulevé", "soulevée",
                             "entraîne", "salle", "musculation", "barre", "poids", "reps",
                             "sets", "push", "pull", "legs", "press", "curl", "row"}
            if any(w in intention_lower for w in workout_words):
                intention_matched_session = True
    except Exception:
        pass

    return jsonify({
        "ok":                        True,
        "outcome":                   outcome,
        "phoenix_streak":            streak,
        "phoenix_best":              best,
        "phoenix_total_burned":      total,
        "intention_matched_session": intention_matched_session,
    })


@ritual_bp.route("/api/ritual/streak")
def api_ritual_streak():
    streak, best, total = _compute_phoenix()
    return jsonify({
        "phoenix_streak":       streak,
        "phoenix_best":         best,
        "phoenix_total_burned": total,
    })


@ritual_bp.route("/api/ritual/checklist", methods=["POST"])
def api_ritual_checklist():
    """Update morning micro-ritual checklist items (D)."""
    import db as _db

    data = request.get_json(silent=True) or {}
    today_str = _today_mtl().isoformat()
    existing  = _db.get_ritual_today(today_str) or {"date": today_str}

    allowed = {"weight_logged", "hydration_done", "mobility_done", "protein_done", "morning_ack"}
    patch = {k: bool(data[k]) for k in allowed if k in data}
    if not patch:
        return jsonify({"error": "no checklist fields provided"}), 400

    ok = _db.upsert_ritual({**existing, **patch})
    return jsonify({"ok": ok, "updated": list(patch.keys())})


@ritual_bp.route("/api/ritual/kill-demon", methods=["POST"])
def api_ritual_kill_demon():
    """Kill a past survived intention directly without going through evening ritual."""
    import db as _db

    data = request.get_json(silent=True) or {}
    demon_date = (data.get("date") or "").strip()
    if not demon_date:
        return jsonify({"error": "date is required"}), 400

    existing = _db.get_ritual_today(demon_date)
    if not existing:
        return jsonify({"error": "Ritual not found for this date"}), 404
    if existing.get("outcome") != "survived":
        return jsonify({"error": "This intention is not in survived state"}), 400

    now_iso = datetime.now(timezone.utc).isoformat()
    patch = {**existing, "outcome": "burned"}
    if not patch.get("evening_at"):
        patch["evening_at"] = now_iso

    ok = _db.upsert_ritual(patch)
    if not ok:
        return jsonify({"error": "Erreur base de données"}), 500

    streak, best, total = _compute_phoenix()
    return jsonify({
        "ok": True,
        "date": demon_date,
        "phoenix_streak": streak,
        "phoenix_best": best,
        "phoenix_total_burned": total,
    })


@ritual_bp.route("/api/ritual/history-full")
def api_ritual_history_full():
    """Full intention history for biography page (F1)."""
    import db as _db

    limit  = min(int(request.args.get("limit", 90)), 365)
    offset = int(request.args.get("offset", 0))
    rows   = _db.get_ritual_history_full(limit=limit, offset=offset)
    total  = _db.count_ritual_entries()

    return jsonify({"entries": rows, "total": total, "limit": limit, "offset": offset})


_ROUTINE_ITEMS = {
    "routine_no_food", "routine_dim_lights", "routine_shower",
    "routine_connection", "routine_deconnect", "routine_priorities_done",
    "routine_bedtime_ok",
}


@ritual_bp.route("/api/ritual/evening_routine", methods=["POST"])
def api_ritual_evening_routine():
    """Auto-save a single evening routine item. Toggles one field at a time."""
    import db as _db

    data = request.get_json(silent=True) or {}
    today_str = _today_mtl().isoformat()

    patch_fields = {k: bool(data[k]) for k in _ROUTINE_ITEMS if k in data}
    if not patch_fields:
        return jsonify({"error": "no routine field provided"}), 400

    existing = _db.get_ritual_today(today_str) or {"date": today_str}
    patch = {**existing, **patch_fields}

    all_done = all(patch.get(item, False) for item in _ROUTINE_ITEMS)
    if all_done and not existing.get("routine_completed_at"):
        patch["routine_completed_at"] = datetime.now(timezone.utc).isoformat()
    elif not all_done:
        patch["routine_completed_at"] = None

    ok = _db.upsert_ritual(patch)
    if not ok:
        return jsonify({"error": "Erreur base de données"}), 500

    return jsonify({
        "ok": True,
        "updated": list(patch_fields.keys()),
        "all_done": all_done,
        "routine_completed_at": patch.get("routine_completed_at"),
    })


