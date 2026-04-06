from flask import Blueprint, jsonify, request

nutrition_bp = Blueprint("nutrition", __name__)


@nutrition_bp.route("/api/nutrition/add", methods=["POST"])
def api_nutrition_add():
    from nutrition import (add_entry as nutrition_add_entry, get_today_totals)
    data  = request.get_json()
    entry = nutrition_add_entry(
        nom       = data.get("nom", ""),
        calories  = float(data.get("calories", 0)),
        proteines = float(data.get("proteines", 0)),
        glucides  = float(data.get("glucides", 0)),
        lipides   = float(data.get("lipides", 0)),
        meal_type = data.get("meal_type"),
    )
    return jsonify({"success": True, "entry": entry, "totals": get_today_totals()})


@nutrition_bp.route("/api/nutrition/delete", methods=["POST"])
def api_nutrition_delete():
    from nutrition import (delete_entry as nutrition_delete_entry, get_today_totals)
    data = request.get_json()
    ok   = nutrition_delete_entry(data.get("id", ""))
    return jsonify({"success": ok, "totals": get_today_totals()})


@nutrition_bp.route("/api/nutrition/edit", methods=["POST"])
def api_nutrition_edit():
    try:
        import db as _db
        from nutrition import get_today_totals
        data     = request.get_json()
        entry_id = data.get("id", "")
        if not entry_id:
            return jsonify({"error": "id manquant"}), 400
        patch = {k: data[k] for k in ("nom", "calories", "proteines", "glucides", "lipides", "quantity")
                 if k in data}
        ok = _db.update_nutrition_entry(entry_id, patch)
        return jsonify({"success": ok, "totals": get_today_totals()})
    except Exception:
        raise


@nutrition_bp.route("/api/nutrition/settings", methods=["POST"])
def api_nutrition_settings():
    from nutrition import (save_settings as save_nutrition_settings)
    data = request.get_json()
    save_nutrition_settings(
        int(data.get("limite_calories", 2200)),
        int(data.get("objectif_proteines", 160)),
        float(data.get("glucides", 0)),
        float(data.get("lipides",  0)),
    )
    return jsonify({"success": True})


@nutrition_bp.route("/api/nutrition_data")
def api_nutrition_data():
    from nutrition import (load_settings as load_nutrition_settings,
                           get_today_entries, get_today_totals, get_recent_days)
    settings = load_nutrition_settings()
    entries  = get_today_entries()
    totals   = get_today_totals()
    history  = get_recent_days(7)
    return jsonify({
        "settings": settings,
        "entries":  entries,
        "totals":   totals,
        "history":  history,
    })
