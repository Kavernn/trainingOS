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

    data       = request.get_json(silent=True) or {}
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
    data = request.get_json(silent=True) or {}
    ok   = nutrition_delete_entry(data.get("id", ""))
    return jsonify({"success": ok, "totals": get_today_totals()})


@nutrition_bp.route("/api/nutrition/edit", methods=["POST"])
def api_nutrition_edit():
    try:
        import db as _db
        from nutrition import get_today_totals
        data     = request.get_json(silent=True) or {}
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
    data = request.get_json(silent=True) or {}
    tc_raw = data.get("training_calories")
    rc_raw = data.get("rest_calories")
    save_nutrition_settings(
        int(data.get("limite_calories",    2200)),
        int(data.get("objectif_proteines", 160)),
        float(data.get("glucides", 0)),
        float(data.get("lipides",  0)),
        training_calories=int(tc_raw) if tc_raw is not None else None,
        rest_calories=int(rc_raw)     if rc_raw is not None else None,
    )
    return jsonify({"success": True})


@nutrition_bp.route("/api/food_catalog", methods=["GET", "POST"])
def api_food_catalog():
    import db as _db
    if request.method == "GET":
        items = _db.get_food_catalog()
        return jsonify({"items": items})
    # POST — save catalog
    data  = request.get_json(silent=True) or {}
    items = data.get("items", [])
    ok    = _db.save_food_catalog(items)
    return jsonify({"success": ok})


@nutrition_bp.route("/api/food/barcode/<code>")
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


# ── Meal Templates ──────────────────────────────────────────────────────────

@nutrition_bp.route("/api/meal_templates", methods=["GET"])
def api_get_meal_templates():
    import db as _db
    return jsonify({"templates": _db.get_meal_templates()})


@nutrition_bp.route("/api/meal_templates", methods=["POST"])
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


@nutrition_bp.route("/api/meal_templates/<template_id>/update", methods=["POST"])
def api_update_meal_template(template_id):
    import db as _db
    data  = request.get_json(silent=True) or {}
    name  = (data.get("name") or "").strip()
    items = data.get("items") or []
    if not name:
        return jsonify({"error": "name requis"}), 422
    ok = _db.update_meal_template(template_id, name, items)
    return jsonify({"success": ok})


@nutrition_bp.route("/api/meal_templates/<template_id>/delete", methods=["POST"])
def api_delete_meal_template(template_id):
    import db as _db
    ok = _db.delete_meal_template(template_id)
    return jsonify({"success": ok})


@nutrition_bp.route("/api/meal_templates/<template_id>/log", methods=["POST"])
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
    for item in (template.get("items") or []):
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

    return jsonify({"success": True, "count": len(entries), "totals": get_today_totals()})


@nutrition_bp.route("/api/nutrition_data")
def api_nutrition_data():
    from nutrition import (load_settings as load_nutrition_settings,
                           get_today_entries, get_today_totals, get_recent_days,
                           _is_training_day)
    settings = load_nutrition_settings()
    entries  = get_today_entries()
    totals   = get_today_totals()
    days     = min(int(request.args.get("days", 7)), 90)
    history  = get_recent_days(days)

    is_training  = _is_training_day()
    today_type   = "training" if is_training else "rest"
    tc = settings.get("training_calories")
    rc = settings.get("rest_calories")
    base = settings.get("limite_calories", 2200) or 2200
    if tc and rc:
        effective_calories = tc if is_training else rc
    elif tc:
        effective_calories = tc
    elif rc:
        effective_calories = rc
    else:
        effective_calories = base

    return jsonify({
        "settings":           settings,
        "entries":            entries,
        "totals":             totals,
        "history":            history,
        "today_type":         today_type,
        "effective_calories": effective_calories,
    })


@nutrition_bp.route("/api/nutrition/correlations")
def api_nutrition_correlations():
    """Join 90 days of nutrition + workout RPE + recovery to surface correlations."""
    import db as _db
    from datetime import date as _date, timedelta
    from nutrition import get_recent_days, load_settings

    settings    = load_settings()
    cal_target  = float(settings.get("limite_calories", 2200)    or 2200)
    prot_target = float(settings.get("objectif_proteines", 160)  or 160)

    nutr_days    = get_recent_days(90)
    nutr_by_date = {d["date"]: d for d in nutr_days}
    sessions     = _db.get_sessions_for_correlations(days=90)
    recovery     = _db.get_recovery_logs(limit=90)
    rec_by_date  = {str(r.get("date", ""))[:10]: r for r in recovery}

    # ── 1. Protein adherence D → next-day RPE ─────────────────────────────
    high_prot_rpe, low_prot_rpe = [], []
    for d_str in sorted(nutr_by_date):
        try:
            next_d = (_date.fromisoformat(d_str) + timedelta(days=1)).isoformat()
        except Exception:
            continue
        rpe = (sessions.get(next_d) or {}).get("rpe")
        if rpe is None:
            continue
        prot = nutr_by_date[d_str].get("proteines", 0) or 0
        (high_prot_rpe if prot >= prot_target * 0.9 else low_prot_rpe).append(float(rpe))

    prot_rpe = None
    if len(high_prot_rpe) >= 3 and len(low_prot_rpe) >= 3:
        avg_h = round(sum(high_prot_rpe) / len(high_prot_rpe), 1)
        avg_l = round(sum(low_prot_rpe)  / len(low_prot_rpe),  1)
        prot_rpe = {
            "high_prot_avg_rpe": avg_h,
            "low_prot_avg_rpe":  avg_l,
            "diff":              round(avg_h - avg_l, 1),
            "sample_high":       len(high_prot_rpe),
            "sample_low":        len(low_prot_rpe),
        }

    # ── 2. Calorie adherence D → same-day recovery score ─────────────────
    on_target_rec, off_target_rec = [], []
    for d_str, nutr in nutr_by_date.items():
        rec = rec_by_date.get(d_str)
        if not rec:
            continue
        scores = []
        if rec.get("soreness") is not None: scores.append(10 - float(rec["soreness"]))
        if rec.get("fatigue")  is not None: scores.append(10 - float(rec["fatigue"]))
        if rec.get("mood")     is not None: scores.append(float(rec["mood"]))
        if len(scores) < 2:
            continue
        rec_score = sum(scores) / len(scores)
        cal = nutr.get("calories", 0) or 0
        (on_target_rec if cal_target * 0.85 <= cal <= cal_target * 1.15 else off_target_rec).append(rec_score)

    cal_rec = None
    if len(on_target_rec) >= 3 and len(off_target_rec) >= 3:
        avg_on  = round(sum(on_target_rec)  / len(on_target_rec),  1)
        avg_off = round(sum(off_target_rec) / len(off_target_rec), 1)
        cal_rec = {
            "on_target_avg":  avg_on,
            "off_target_avg": avg_off,
            "diff":           round(avg_on - avg_off, 1),
            "sample_on":      len(on_target_rec),
            "sample_off":     len(off_target_rec),
        }

    # ── 3. Session volume D → next-day calorie intake ────────────────────
    vols = [v["session_volume"] for v in sessions.values() if v.get("session_volume")]
    vol_cal = None
    if vols:
        vol_median   = sorted(vols)[len(vols) // 2]
        high_vol_cal, low_vol_cal = [], []
        for d_str, sess in sessions.items():
            sv = sess.get("session_volume")
            if sv is None:
                continue
            try:
                next_d = (_date.fromisoformat(d_str) + timedelta(days=1)).isoformat()
            except Exception:
                continue
            cal = (nutr_by_date.get(next_d) or {}).get("calories", 0) or 0
            if cal == 0:
                continue
            (high_vol_cal if sv >= vol_median else low_vol_cal).append(float(cal))
        if len(high_vol_cal) >= 3 and len(low_vol_cal) >= 3:
            avg_h = round(sum(high_vol_cal) / len(high_vol_cal))
            avg_l = round(sum(low_vol_cal)  / len(low_vol_cal))
            vol_cal = {
                "high_vol_avg_cal": avg_h,
                "low_vol_avg_cal":  avg_l,
                "diff":             avg_h - avg_l,
            }

    return jsonify({
        "prot_rpe":   prot_rpe,
        "cal_rec":    cal_rec,
        "vol_cal":    vol_cal,
        "sample_days": len(nutr_by_date),
    })
