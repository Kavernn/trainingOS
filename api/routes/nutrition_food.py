from flask import Blueprint, jsonify, request
import logging

logger = logging.getLogger("trainingos")
nutrition_food_bp = Blueprint("nutrition_food", __name__)


@nutrition_food_bp.route("/api/food_catalog", methods=["GET", "POST"])
def api_food_catalog():
    import db as _db
    if request.method == "GET":
        items = _db.get_food_catalog()
        return jsonify({"items": items})
    data  = request.get_json(silent=True) or {}
    items = data.get("items", [])
    ok    = _db.save_food_catalog(items)
    return jsonify({"success": ok})
