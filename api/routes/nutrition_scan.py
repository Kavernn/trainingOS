from flask import Blueprint, jsonify, request
import logging

logger = logging.getLogger("trainingos")
nutrition_scan_bp = Blueprint("nutrition_scan", __name__)


@nutrition_scan_bp.route("/api/nutrition/scan-label", methods=["POST"])
def api_nutrition_scan_label():
    """Analyse une étiquette nutritionnelle via Claude Vision et retourne les macros scaled."""
    from utils import _ai_rate_check
    if not _ai_rate_check():
        return jsonify({"error": "Trop de requêtes — réessaie dans quelques minutes."}), 429

    import os, json as _json
    import anthropic as _anthropic

    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not api_key:
        return jsonify({"error": "ANTHROPIC_API_KEY manquant"}), 500

    data       = request.get_json(silent=True) or {}
    image_b64  = data.get("image_base64", "")
    media_type = data.get("media_type", "image/jpeg")
    quantity   = float(data.get("quantity", 1) or 1)
    unit       = data.get("unit", "serving")  # serving | g | ml

    if not image_b64:
        return jsonify({"error": "Image manquante"}), 400

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

        serving_size = float(result.get("serving_size") or 1)
        serving_unit = (result.get("serving_unit") or "g").lower().strip()
        per = result.get("per_serving", {})

        if unit == "serving":
            scale = quantity
        elif unit in ("g", "ml") and serving_unit in ("g", "ml") and serving_size > 0:
            scale = quantity / serving_size
        else:
            scale = quantity / serving_size if serving_size > 0 else quantity

        scaled_cal   = round(float(per.get("calories",  0)) * scale)
        scaled_prot  = round(float(per.get("protein_g", 0)) * scale, 1)
        scaled_carbs = round(float(per.get("carbs_g",   0)) * scale, 1)
        scaled_fat   = round(float(per.get("fat_g",     0)) * scale, 1)

        def _scan_warnings(calories, protein_g, carbs_g, fat_g):
            warnings = []
            computed = protein_g * 4 + carbs_g * 4 + fat_g * 9
            if calories > 0 and computed > 0:
                ratio = computed / calories
                if ratio < 0.70 or ratio > 1.30:
                    warnings.append(
                        f"Incohérence macros/calories : macros totalisent {round(computed)} kcal "
                        f"pour {round(calories)} kcal déclarées."
                    )
            if calories > 1500:
                warnings.append("Calories élevées — vérifie que la quantité est correcte.")
            return warnings

        validation_warnings = _scan_warnings(scaled_cal, scaled_prot, scaled_carbs, scaled_fat)

        return jsonify({
            "nom":                  result.get("product_name") or "Aliment scanné",
            "calories":             scaled_cal,
            "proteines":            scaled_prot,
            "glucides":             scaled_carbs,
            "lipides":              scaled_fat,
            "fibres":               round(float(per.get("fiber_g",   0)) * scale, 1),
            "sodium_mg":            round(float(per.get("sodium_mg", 0)) * scale, 1),
            "requires_confirmation": len(validation_warnings) > 0,
            "validation_warnings":  validation_warnings,
        })

    except _anthropic.AuthenticationError:
        return jsonify({"error": "Clé ANTHROPIC_API_KEY invalide"}), 500
    except Exception as e:
        logger.error("scan-label error: %s", e)
        return jsonify({"error": "Erreur lors de l'analyse"}), 500
