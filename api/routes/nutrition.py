from flask import Blueprint, jsonify, request
import logging

logger = logging.getLogger("trainingos")
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
    for field in ("proteines", "glucides", "lipides"):
        val = float(data.get(field, 0))
        if val < 0 or val > 10000:
            return jsonify({"error": f"{field} invalide (0–10000)"}), 422
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

    dtt_raw = data.get("day_type_targets")
    day_type_targets = None
    if isinstance(dtt_raw, dict):
        day_type_targets = {}
        for key in ("light", "moderate", "heavy", "rest"):
            t = dtt_raw.get(key) or {}
            if t:
                day_type_targets[key] = {
                    "calories": int(t.get("calories", 0)),
                    "glucides": int(t.get("glucides", 0)),
                }

    save_nutrition_settings(
        int(data.get("limite_calories",    2400)),
        int(data.get("objectif_proteines", 180)),
        float(data.get("glucides", 235)),
        float(data.get("lipides",  75)),
        day_type_targets=day_type_targets,
    )
    return jsonify({"success": True})


@nutrition_bp.route("/api/nutrition/tdee", methods=["POST"])
def api_nutrition_tdee():
    """
    Recalcule BMR/TDEE depuis le profil utilisateur et met à jour nutrition_settings.
    POST sans body — lit user_profile automatiquement.
    """
    import db as _db
    from tdee import compute_tdee, compute_dynamic_day_targets
    from nutrition import save_settings as save_nutrition_settings

    profile = _db.get_profile() or {}
    tdee_data = compute_tdee(profile)
    if not tdee_data:
        return jsonify({"error": "Profil incomplet — renseigne poids, taille et âge."}), 422

    weight_lbs = float(profile.get("weight") or 0)
    weight_kg  = weight_lbs * 0.453592 if weight_lbs else None
    dtt = compute_dynamic_day_targets(weight_kg, tdee_data["calorie_target"]) if weight_kg else None

    save_nutrition_settings(
        tdee_data["calorie_target"],
        tdee_data["objectif_proteines"],
        float(tdee_data["glucides"]),
        float(tdee_data["lipides"]),
        day_type_targets=dtt,
    )

    # Persister les méta TDEE dans nutrition_settings
    import db as _db2
    _db2.update_nutrition_settings({
        "bmr_kcal":          tdee_data["bmr_kcal"],
        "tdee_kcal":         tdee_data["tdee_kcal"],
        "calorie_target":    tdee_data["calorie_target"],
        "activity_factor":   tdee_data["activity_factor"],
        "sessions_per_week": tdee_data["sessions_per_week"],
        "formula_used":      tdee_data["formula_used"],
        "goal_phase":        tdee_data["goal_phase"],
    })

    return jsonify({"success": True, **tdee_data})


@nutrition_bp.route("/api/nutrition/adaptive-check", methods=["GET"])
def api_nutrition_adaptive_check():
    """
    Évalue la progression du poids sur 14 jours et propose ±150 kcal si nécessaire.
    Lecture seule — l'utilisateur applique l'ajustement manuellement.
    """
    from tdee import check_weight_progress
    from nutrition import load_settings

    settings = load_settings()
    goal     = settings.get("goal_phase") or "maintain"
    cal      = int(settings.get("limite_calories") or 2400)

    result = check_weight_progress(goal, cal)
    if result is None:
        return jsonify({
            "available": False,
            "reason": "Moins de 14 pesées — continue à enregistrer ton poids quotidiennement.",
        })
    return jsonify({"available": True, "current_target_kcal": cal, **result})


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


@nutrition_bp.route("/api/nutrition_data")
def api_nutrition_data():
    from nutrition import (load_settings as load_nutrition_settings,
                           get_today_entries, get_today_totals, get_recent_days,
                           _get_day_intensity)
    settings = load_nutrition_settings()
    entries  = get_today_entries()
    totals   = get_today_totals()
    days     = min(int(request.args.get("days", 7)), 90)
    history  = get_recent_days(days)

    intensity, today_session = _get_day_intensity()
    dtt         = settings.get("day_type_targets", {})
    type_target = dtt.get(intensity, {})

    effective_calories = type_target.get("calories") or settings.get("limite_calories", 2400) or 2400
    effective_glucides = type_target.get("glucides")  or settings.get("glucides", 235) or 235

    return jsonify({
        "settings":           settings,
        "entries":            entries,
        "totals":             totals,
        "history":            history,
        "today_type":         intensity,
        "today_session":      today_session,
        "effective_calories": effective_calories,
        "effective_glucides": effective_glucides,
    })


@nutrition_bp.route("/api/nutrition/correlations")
def api_nutrition_correlations():
    """Join 90 days of nutrition + workout RPE + recovery to surface correlations."""
    import db as _db
    from datetime import date as _date, timedelta
    from nutrition import get_recent_days, load_settings

    settings    = load_settings()
    cal_target  = float(settings.get("limite_calories", 2400)    or 2400)
    prot_target = float(settings.get("objectif_proteines", 180)  or 180)

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

    _CORR_MIN_N = 12  # minimum statistique valide (Curran-Everett 2018)

    prot_rpe = None
    if len(high_prot_rpe) >= _CORR_MIN_N and len(low_prot_rpe) >= _CORR_MIN_N:
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
    if len(on_target_rec) >= _CORR_MIN_N and len(off_target_rec) >= _CORR_MIN_N:
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
        if len(high_vol_cal) >= _CORR_MIN_N and len(low_vol_cal) >= _CORR_MIN_N:
            avg_h = round(sum(high_vol_cal) / len(high_vol_cal))
            avg_l = round(sum(low_vol_cal)  / len(low_vol_cal))
            vol_cal = {
                "high_vol_avg_cal": avg_h,
                "low_vol_avg_cal":  avg_l,
                "diff":             avg_h - avg_l,
            }

    return jsonify({
        "prot_rpe":          prot_rpe,
        "cal_rec":           cal_rec,
        "vol_cal":           vol_cal,
        "sample_days":       len(nutr_by_date),
        "insufficient_data": prot_rpe is None and cal_rec is None and vol_cal is None,
        "min_n_required":    _CORR_MIN_N,
    })


@nutrition_bp.route("/api/nutrition/hydration", methods=["GET", "POST"])
def api_hydration():
    """
    GET  — objectif hydrique du jour (35 ml/kg + 600 ml si séance) + total loggué.
    POST — quick-add (défaut 250 ml, paramètre ml accepté).

    Référence objectif : Cheuvront & Kenefick 2014 (2 % déshydratation = -10-20 % performance).
    """
    import db as _db
    from datetime import date

    if request.method == "GET":
        profile    = _db.get_profile() or {}
        weight_lbs = float(profile.get("weight") or 0)
        weight_kg  = weight_lbs * 0.453592 if weight_lbs else 75.0
        base_ml    = round(weight_kg * 35)

        today    = date.today().isoformat()
        sessions = _db.get_workout_sessions(limit=7) or []
        had_session = any(
            s.get("date") == today and s.get("completed")
            for s in sessions
        )
        target_ml = base_ml + (600 if had_session else 0)
        logged_ml = _db.get_hydration_today()

        return jsonify({
            "target_ml":    target_ml,
            "logged_ml":    logged_ml,
            "remaining_ml": max(0, target_ml - logged_ml),
            "pct":          round(logged_ml / target_ml * 100) if target_ml else 0,
            "weight_kg":    round(weight_kg, 1),
            "session_bonus": 600 if had_session else 0,
        })

    # POST — quick-add
    data   = request.get_json(silent=True) or {}
    amount = int(data.get("ml", 250))
    if amount <= 0 or amount > 2000:
        return jsonify({"error": "Quantité invalide (1–2000 ml)"}), 422
    _db.log_hydration(amount)
    return jsonify({"success": True, "added_ml": amount})
