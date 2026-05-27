from flask import Blueprint, jsonify, request
import logging

logger = logging.getLogger("trainingos")
nutrition_templates_bp = Blueprint("nutrition_templates", __name__)


@nutrition_templates_bp.route("/api/meal_templates", methods=["GET"])
def api_get_meal_templates():
    import db as _db
    return jsonify({"templates": _db.get_meal_templates()})


@nutrition_templates_bp.route("/api/meal_templates", methods=["POST"])
def api_create_meal_template():
    import db as _db
    data  = request.get_json(silent=True) or {}
    name  = (data.get("name") or "").strip()
    items = data.get("items") or []
    if not name:
        return jsonify({"error": "name requis"}), 422
    result = _db.create_meal_template(name, items)
    if result is None:
        return jsonify({"error": "Erreur lors de la création"}), 500
    return jsonify({"success": True, "template": result})


@nutrition_templates_bp.route("/api/meal_templates/<template_id>/update", methods=["POST"])
def api_update_meal_template(template_id):
    import db as _db
    data  = request.get_json(silent=True) or {}
    name  = (data.get("name") or "").strip()
    items = data.get("items") or []
    if not name:
        return jsonify({"error": "name requis"}), 422
    ok = _db.update_meal_template(template_id, name, items)
    return jsonify({"success": ok})


@nutrition_templates_bp.route("/api/meal_templates/<template_id>/delete", methods=["POST"])
def api_delete_meal_template(template_id):
    import db as _db
    ok = _db.delete_meal_template(template_id)
    return jsonify({"success": ok})


@nutrition_templates_bp.route("/api/meal_templates/<template_id>/log", methods=["POST"])
def api_log_meal_template(template_id):
    """Log all items from a template as today's nutrition entries."""
    import db as _db
    from nutrition import add_entry as _add_entry, get_today_totals
    data      = request.get_json(silent=True) or {}
    meal_type = data.get("meal_type")

    templates = _db.get_meal_templates()
    template  = next((t for t in templates if str(t.get("id")) == template_id), None)
    if template is None:
        return jsonify({"error": "Template introuvable"}), 404

    entries = []
    errors  = []
    for item in (template.get("items") or []):
        try:
            entry = _add_entry(
                nom       = str(item.get("name") or item.get("nom") or ""),
                calories  = float(item.get("calories") or 0),
                proteines = float(item.get("proteines") or 0),
                glucides  = float(item.get("glucides") or 0),
                lipides   = float(item.get("lipides") or 0),
                meal_type = meal_type,
                source    = "template",
            )
            entries.append(entry)
        except Exception as e:
            logger.error("meal_template log item '%s' error: %s", item.get("name", "?"), e)
            errors.append(str(item.get("name") or item.get("nom") or "?"))

    if errors and not entries:
        return jsonify({"error": f"Aucun item loggé. Échecs : {errors}"}), 500
    return jsonify({"success": True, "count": len(entries), "errors": errors, "totals": get_today_totals()})
