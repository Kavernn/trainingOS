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


@nutrition_food_bp.route("/api/food/barcode/<code>")
def api_food_barcode(code):
    """Query Open Food Facts for a product by EAN/UPC barcode."""
    import requests as _req
    try:
        resp = _req.get(
            f"https://world.openfoodfacts.org/api/v0/product/{code}.json",
            timeout=8,
            headers={"User-Agent": "TrainingOS/1.0 (contact: kavernn@gmail.com)"},
        )
        data = resp.json()
    except Exception:
        return jsonify({"error": "Impossible de joindre Open Food Facts"}), 503

    if data.get("status") != 1:
        return jsonify({"error": "Produit introuvable"}), 404

    product    = data.get("product", {})
    nutriments = product.get("nutriments", {})

    nom = (
        product.get("product_name_fr")
        or product.get("product_name_en")
        or product.get("product_name")
        or "Produit inconnu"
    ).strip()

    serving_size = (product.get("serving_size") or "").strip() or None

    def n(key):
        v = nutriments.get(key)
        return float(v) if v is not None else 0.0

    per_100g = {
        "calories":  round(n("energy-kcal_100g")),
        "proteines": round(n("proteins_100g"), 1),
        "glucides":  round(n("carbohydrates_100g"), 1),
        "lipides":   round(n("fat_100g"), 1),
    }

    cal_s = nutriments.get("energy-kcal_serving")
    per_serving = None
    if cal_s is not None:
        per_serving = {
            "calories":  round(float(cal_s)),
            "proteines": round(n("proteins_serving"), 1),
            "glucides":  round(n("carbohydrates_serving"), 1),
            "lipides":   round(n("fat_serving"), 1),
        }

    return jsonify({
        "nom":          nom,
        "serving_size": serving_size,
        "per_100g":     per_100g,
        "per_serving":  per_serving,
    })
