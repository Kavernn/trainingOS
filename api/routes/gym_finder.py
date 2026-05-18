from flask import Blueprint, jsonify, request
from datetime import datetime, timezone

gym_finder_bp = Blueprint("gym_finder", __name__)


# ── Crowdsource bulk fetch ─────────────────────────────────────

@gym_finder_bp.route("/api/gyms/crowdsource_bulk", methods=["POST"])
def crowdsource_bulk():
    data = request.get_json(silent=True) or {}
    gym_ids = data.get("gym_ids", [])
    if not gym_ids:
        return jsonify({})

    result = {}
    for gym_id in gym_ids[:50]:
        cs = _aggregate_crowdsource(gym_id)
        if cs:
            result[gym_id] = cs

    return jsonify(result)


# ── Submit contribution ────────────────────────────────────────

@gym_finder_bp.route("/api/gyms/contribute", methods=["POST"])
def contribute():
    data = request.get_json(silent=True) or {}
    if not data.get("gymId"):
        return jsonify({"error": "gymId required"}), 400
    _save_contribution(data)
    return jsonify({"ok": True})


# ── Log gym visit ──────────────────────────────────────────────

@gym_finder_bp.route("/api/gyms/history", methods=["POST"])
def log_history():
    data = request.get_json(silent=True) or {}
    _save_gym_visit(data)
    return jsonify({"ok": True})


# ── Internal helpers ───────────────────────────────────────────

def _aggregate_crowdsource(gym_id: str) -> dict | None:
    try:
        import db as _db
        if not _db._client:
            return None

        rows = (_db._client.table("gym_contributions")
                .select("*")
                .eq("gym_id", gym_id)
                .execute().data or [])

        if not rows:
            return None

        equipment_counts: dict[str, int] = {}
        drop_in_prices, vibe_hardcore, vibe_crowded, vibe_music = [], [], [], []

        for row in rows:
            for eq in (row.get("equipment") or []):
                equipment_counts[eq] = equipment_counts.get(eq, 0) + 1
            if row.get("drop_in_price") is not None:
                drop_in_prices.append(float(row["drop_in_price"]))
            if row.get("vibe_hardcore"):
                vibe_hardcore.append(int(row["vibe_hardcore"]))
            if row.get("vibe_crowded"):
                vibe_crowded.append(int(row["vibe_crowded"]))
            if row.get("vibe_music"):
                vibe_music.append(int(row["vibe_music"]))

        threshold = max(1, len(rows) // 2)
        confirmed = [k for k, v in equipment_counts.items() if v >= threshold]

        last = max(rows, key=lambda r: r.get("created_at", ""), default=None)

        return {
            "dropInPrice": round(sum(drop_in_prices) / len(drop_in_prices), 2) if drop_in_prices else None,
            "equipment": confirmed,
            "vibeHardcore": round(sum(vibe_hardcore) / len(vibe_hardcore)) if vibe_hardcore else None,
            "vibeCrowded": round(sum(vibe_crowded) / len(vibe_crowded)) if vibe_crowded else None,
            "vibeMusic": round(sum(vibe_music) / len(vibe_music)) if vibe_music else None,
            "contributionCount": len(rows),
            "lastUpdated": (last.get("created_at") or "")[:10] if last else None,
        }
    except Exception:
        return None


def _save_contribution(data: dict) -> None:
    try:
        import db as _db
        if not _db._client:
            return
        _db._client.table("gym_contributions").insert({
            "gym_id":       data.get("gymId"),
            "gym_name":     data.get("gymName"),
            "latitude":     data.get("latitude"),
            "longitude":    data.get("longitude"),
            "drop_in_price": data.get("dropInPrice"),
            "equipment":    data.get("equipment", []),
            "vibe_hardcore": data.get("vibeHardcore"),
            "vibe_crowded":  data.get("vibeCrowded"),
            "vibe_music":    data.get("vibeMusic"),
            "created_at":   datetime.now(timezone.utc).isoformat(),
        }).execute()
    except Exception:
        pass


def _save_gym_visit(data: dict) -> None:
    try:
        import db as _db
        if not _db._client:
            return
        _db._client.table("user_gym_history").insert({
            "gym_id":     data.get("gym_id"),
            "gym_name":   data.get("gym_name"),
            "latitude":   data.get("latitude"),
            "longitude":  data.get("longitude"),
            "visited_at": data.get("visited_at", datetime.now(timezone.utc).isoformat()),
        }).execute()
    except Exception:
        pass
