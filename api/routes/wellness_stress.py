from flask import Blueprint, jsonify, request

wellness_stress_bp = Blueprint("wellness_stress", __name__)


@wellness_stress_bp.route("/api/life_stress/score")
def api_life_stress_score():
    """
    Life Stress Score pour un jour donné (0 = surmenage, 100 = récupération optimale).
    ?date=YYYY-MM-DD  (défaut : aujourd'hui)
    ?refresh=true     (force le recalcul)
    """
    from life_stress_engine import get_life_stress_score, refresh_life_stress_score
    target_date = request.args.get("date")
    force_refresh = request.args.get("refresh", "false").lower() == "true"
    if force_refresh:
        return jsonify(refresh_life_stress_score(target_date))
    return jsonify(get_life_stress_score(target_date))


@wellness_stress_bp.route("/api/life_stress/trend")
def api_life_stress_trend():
    """
    Tendance LSS sur les N derniers jours (du plus récent au plus ancien).
    ?days=7  (défaut : 7, max : 90)
    """
    from life_stress_engine import get_recent_life_stress_trend
    try:
        days = int(request.args.get("days", 7))
        days = max(1, min(days, 90))
    except ValueError:
        days = 7
    return jsonify(get_recent_life_stress_trend(days))


@wellness_stress_bp.route("/api/pss/questions")
def api_pss_questions():
    """
    Retourne les questions PSS à afficher.
    ?short=true  → PSS-4 (4 questions, défaut : false)
    """
    from pss import get_questions
    is_short = request.args.get("short", "false").lower() == "true"
    return jsonify(get_questions(is_short))


@wellness_stress_bp.route("/api/pss/submit", methods=["POST"])
def api_pss_submit():
    """
    Soumet un questionnaire PSS et persiste le résultat.

    Body JSON :
    {
      "responses":       [int × 10 ou × 4],
      "is_short":        bool (défaut false),
      "notes":           str (optionnel),
      "triggers":        [str] (optionnel, max 2),
      "trigger_ratings": { "travail": 3 } (optionnel)
    }
    """
    from pss import save_pss_record
    data = request.get_json(silent=True) or {}
    responses = data.get("responses")
    if not responses:
        return jsonify({"error": "responses requis"}), 400

    try:
        parsed = [int(r) for r in responses]
        if any(v < 0 or v > 4 for v in parsed):
            return jsonify({"error": "Chaque réponse doit être entre 0 et 4"}), 422
        record = save_pss_record(
            responses       = parsed,
            is_short        = bool(data.get("is_short", False)),
            notes           = data.get("notes"),
            triggers        = data.get("triggers"),
            trigger_ratings = data.get("trigger_ratings"),
        )
        from routes.daily_brief import invalidate_cache as _brief_invalidate
        _brief_invalidate()
        return jsonify(record), 201
    except ValueError as e:
        return jsonify({"error": str(e)}), 422
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@wellness_stress_bp.route("/api/pss/history")
def api_pss_history():
    """
    Historique des enregistrements PSS.
    ?type=full|short  (défaut : tous)
    ?limit=20
    """
    from pss import get_history as pss_get_history
    pss_type = request.args.get("type")
    try:
        limit = int(request.args.get("limit", 20))
    except ValueError:
        limit = 20
    return jsonify(pss_get_history(pss_type, limit))


@wellness_stress_bp.route("/api/pss/check_due")
def api_pss_check_due():
    """
    Vérifie si un test PSS est dû.
    ?type=full|short  (défaut : full)
    """
    from pss import check_due as pss_check_due
    pss_type = request.args.get("type", "full")
    return jsonify(pss_check_due(pss_type))


@wellness_stress_bp.route("/api/pss/delete", methods=["POST"])
def api_pss_delete():
    """Supprime un enregistrement PSS par id. Body JSON: {"id": "..."}"""
    import db as _db_pss
    data = request.get_json() or {}
    record_id = data.get("id")
    if not record_id:
        return jsonify({"error": "id requis"}), 400
    if _db_pss._client is None:
        return jsonify({"error": "base de données non disponible"}), 503
    try:
        _db_pss._client.table("pss_records").delete().eq("id", record_id).execute()
        from routes.daily_brief import invalidate_cache as _brief_invalidate
        _brief_invalidate()
        return jsonify({"success": True})
    except Exception:
        raise


# ── DASS-21 ───────────────────────────────────────────────────────────────────

@wellness_stress_bp.route("/api/dass/questions")
def api_dass_questions():
    """Retourne les 21 questions DASS avec leur sous-échelle."""
    from dass import get_questions
    return jsonify(get_questions())


@wellness_stress_bp.route("/api/dass/submit", methods=["POST"])
def api_dass_submit():
    """
    Soumet un questionnaire DASS-21 et persiste le résultat.

    Body JSON :
    {
      "responses": [int × 21],   // 0-3 par item
      "notes":     str (optionnel)
    }
    """
    from dass import save_dass_record
    data = request.get_json(silent=True) or {}
    responses = data.get("responses")
    if not responses:
        return jsonify({"error": "responses requis (21 entiers 0-3)"}), 400
    try:
        parsed = [int(r) for r in responses]
        if any(v < 0 or v > 3 for v in parsed):
            return jsonify({"error": "Chaque réponse doit être entre 0 et 3"}), 422
        record = save_dass_record(responses=parsed, notes=data.get("notes"))
        return jsonify(record), 201
    except ValueError as e:
        return jsonify({"error": str(e)}), 422
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@wellness_stress_bp.route("/api/dass/history")
def api_dass_history():
    """
    Historique des enregistrements DASS-21.
    ?limit=12
    """
    from dass import get_history as dass_get_history
    try:
        limit = int(request.args.get("limit", 12))
    except ValueError:
        limit = 12
    return jsonify(dass_get_history(limit))


@wellness_stress_bp.route("/api/dass/check_due")
def api_dass_check_due():
    """Vérifie si un DASS-21 est dû (mensuel)."""
    from dass import check_due as dass_check_due
    return jsonify(dass_check_due())


@wellness_stress_bp.route("/api/dass/latest")
def api_dass_latest():
    """Retourne le dernier enregistrement DASS-21."""
    from dass import get_latest as dass_get_latest
    result = dass_get_latest()
    if not result:
        return jsonify(None)
    return jsonify(result)


# ── Sommeil ────────────────────────────────────────────────────────────────────

@wellness_stress_bp.route("/api/sleep/log", methods=["POST"])
def api_sleep_log():
    from sleep import save_sleep_entry
    data = request.get_json() or {}
    bedtime   = data.get("bedtime")
    wake_time = data.get("wake_time")
    quality   = data.get("quality")
    if not bedtime or not wake_time or quality is None:
        return jsonify({"error": "bedtime, wake_time et quality requis"}), 400
    quality_int = int(quality)
    if not (1 <= quality_int <= 5):
        return jsonify({"error": "quality doit être entre 1 et 5"}), 422
    try:
        entry = save_sleep_entry(
            bedtime   = bedtime,
            wake_time = wake_time,
            quality   = quality_int,
            notes     = data.get("notes"),
        )
        return jsonify(entry)
    except Exception:
        raise

@wellness_stress_bp.route("/api/sleep/history")
def api_sleep_history():
    from sleep import get_history as sleep_get_history
    try:
        limit  = int(request.args.get("limit", 20))
        offset = int(request.args.get("offset", 0))
    except ValueError:
        limit, offset = 20, 0
    return jsonify(sleep_get_history(limit, offset))

@wellness_stress_bp.route("/api/sleep/today")
def api_sleep_today():
    from sleep import get_today as sleep_get_today
    entry = sleep_get_today()
    return jsonify(entry if entry else {})

@wellness_stress_bp.route("/api/sleep/stats")
def api_sleep_stats():
    from sleep import get_stats as sleep_get_stats
    return jsonify(sleep_get_stats())

@wellness_stress_bp.route("/api/sleep/delete", methods=["POST"])
def api_sleep_delete():
    from sleep import delete_entry as sleep_delete_entry
    data = request.get_json() or {}
    record_id = data.get("id")
    if not record_id:
        return jsonify({"error": "id requis"}), 400
    if sleep_delete_entry(record_id):
        return jsonify({"success": True})
    return jsonify({"error": "introuvable"}), 404
