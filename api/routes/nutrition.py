from flask import Blueprint, jsonify, request

nutrition_bp = Blueprint("nutrition", __name__)


@nutrition_bp.route("/api/nutrition/add", methods=["POST"])
def api_nutrition_add():
    from nutrition import (add_entry as nutrition_add_entry, get_today_totals)
    data  = request.get_json() or {}
    if not data.get("nom", "").strip():
        return jsonify({"error": "nom requis"}), 422
    calories_val = float(data.get("calories", 0))
    if calories_val < 0:
        return jsonify({"error": "calories ne peut pas être négatif"}), 422
    entry = nutrition_add_entry(
        nom       = data.get("nom", ""),
        calories  = calories_val,
        proteines = float(data.get("proteines", 0)),
        glucides  = float(data.get("glucides", 0)),
        lipides   = float(data.get("lipides", 0)),
        meal_type = data.get("meal_type"),
        source    = data.get("source", "manual"),
    )
    return jsonify({"success": True, "entry": entry, "totals": get_today_totals()})


@nutrition_bp.route("/api/nutrition/scan-label", methods=["POST"])
def api_nutrition_scan_label():
    """Analyse une étiquette nutritionnelle via Claude Vision et retourne les macros scaled."""
    from utils import _ai_rate_check
    if not _ai_rate_check():
        return jsonify({"error": "Trop de requêtes — réessaie dans quelques minutes."}), 429

    import os, json as _json
    import anthropic as _anthropic
    import logging
    logger = logging.getLogger("trainingos")

    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not api_key:
        return jsonify({"error": "ANTHROPIC_API_KEY manquant"}), 500

    data       = request.get_json()
    image_b64  = data.get("image_base64", "")
    media_type = data.get("media_type", "image/jpeg")
    quantity   = float(data.get("quantity", 1) or 1)
    unit       = data.get("unit", "serving")  # serving | g | ml

    if not image_b64:
        return jsonify({"error": "Image manquante"}), 400

    # Valider le media_type
    if media_type not in {"image/jpeg", "image/png", "image/gif", "image/webp"}:
        media_type = "image/jpeg"

    try:
        client = _anthropic.Anthropic(api_key=api_key)
        message = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=400,
            messages=[{
                "role": "user",
                "content": [
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": media_type,
                            "data": image_b64,
                        }
                    },
                    {
                        "type": "text",
                        "text": (
                            "Tu analyses une étiquette nutritionnelle. "
                            "Réponds UNIQUEMENT avec du JSON valide, sans texte avant ni après.\n\n"
                            "Format attendu:\n"
                            '{"product_name":"nom du produit si visible, sinon Aliment scanné",'
                            '"serving_size":30,"serving_unit":"g",'
                            '"per_serving":{"calories":120,"protein_g":5.0,"carbs_g":18.0,'
                            '"fat_g":3.5,"fiber_g":2.0,"sodium_mg":150}}\n\n'
                            "Si l'étiquette est illisible ou si ce n'est pas une étiquette nutritionnelle:\n"
                            '{"error":"Étiquette illisible ou non reconnue"}'
                        )
                    }
                ]
            }]
        )

        raw = message.content[0].text.strip()
        start = raw.find('{')
        end   = raw.rfind('}') + 1
        if start == -1 or end == 0:
            return jsonify({"error": "Réponse non structurée du modèle"}), 500

        result = _json.loads(raw[start:end])

        if "error" in result:
            return jsonify({"error": result["error"]}), 422

        # Scaling selon quantité et unité saisies
        serving_size = float(result.get("serving_size") or 1)
        serving_unit = (result.get("serving_unit") or "g").lower().strip()
        per = result.get("per_serving", {})

        if unit == "serving":
            scale = quantity
        elif unit in ("g", "ml") and serving_unit in ("g", "ml") and serving_size > 0:
            # g and ml are treated as equivalent mass/volume units for scaling purposes
            scale = quantity / serving_size
        else:
            scale = quantity / serving_size if serving_size > 0 else quantity

        return jsonify({
            "nom":       result.get("product_name") or "Aliment scanné",
            "calories":  round(float(per.get("calories",  0)) * scale),
            "proteines": round(float(per.get("protein_g", 0)) * scale, 1),
            "glucides":  round(float(per.get("carbs_g",   0)) * scale, 1),
            "lipides":   round(float(per.get("fat_g",     0)) * scale, 1),
            "fibres":    round(float(per.get("fiber_g",   0)) * scale, 1),
            "sodium_mg": round(float(per.get("sodium_mg", 0)) * scale, 1),
        })

    except _anthropic.AuthenticationError:
        return jsonify({"error": "Clé ANTHROPIC_API_KEY invalide"}), 500
    except Exception as e:
        logger.error("scan-label error: %s", e)
        return jsonify({"error": "Erreur lors de l'analyse"}), 500


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


@nutrition_bp.route("/api/food_catalog", methods=["GET", "POST"])
def api_food_catalog():
    import db as _db
    if request.method == "GET":
        items = _db.get_food_catalog()
        return jsonify({"items": items})
    # POST — save catalog
    data  = request.get_json()
    items = data.get("items", [])
    ok    = _db.save_food_catalog(items)
    return jsonify({"success": ok})


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
