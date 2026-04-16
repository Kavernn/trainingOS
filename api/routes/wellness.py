from flask import Blueprint, jsonify, request
from datetime import date

wellness_bp = Blueprint("wellness", __name__)


# ── Cardio ───────────────────────────────────────────────────

@wellness_bp.route("/api/cardio_data")
def api_cardio_data():
    import db as _db
    log = _db.get_cardio_logs() or []
    return jsonify({"cardio_log": sorted(log, key=lambda x: x.get("date", ""), reverse=True)})

@wellness_bp.route("/api/log_cardio", methods=["POST"])
def api_log_cardio():
    import db as _db
    data = request.get_json()
    entry = {
        "date":         data.get("date", date.today().isoformat()),
        "type":         data.get("type", "course"),
        "duration_min": data.get("duration_min"),
        "distance_km":  data.get("distance_km"),
        "avg_pace":     data.get("avg_pace"),
        "avg_hr":       data.get("avg_hr"),
        "cadence":      data.get("cadence"),
        "calories":     data.get("calories"),
        "rpe":          data.get("rpe"),
        "notes":        data.get("notes", ""),
    }
    _db.insert_cardio_log(entry)
    return jsonify({"ok": True})

@wellness_bp.route("/api/delete_cardio", methods=["POST"])
def api_delete_cardio():
    import db as _db
    data = request.get_json()
    _db.delete_cardio_log(data.get("date", ""), data.get("type", ""))
    return jsonify({"ok": True})


# ── Récupération ──────────────────────────────────────────────

@wellness_bp.route("/api/recovery_data")
def api_recovery_data():
    import db as _db
    log = _db.get_recovery_logs() or []
    return jsonify({"recovery_log": sorted(log, key=lambda x: x.get("date", ""), reverse=True)})

@wellness_bp.route("/api/log_recovery", methods=["POST"])
def api_log_recovery():
    import db as _db
    data  = request.get_json()
    entry = {
        "date":          data.get("date", date.today().isoformat()),
        "sleep_hours":   data.get("sleep_hours"),
        "sleep_quality": data.get("sleep_quality"),
        "resting_hr":    data.get("resting_hr"),
        "hrv":           data.get("hrv"),
        "steps":         data.get("steps"),
        "soreness":      data.get("soreness"),
        "notes":         data.get("notes", ""),
        "source":        "manual",
    }
    _db.upsert_recovery_log(entry)
    return jsonify({"ok": True})

@wellness_bp.route("/api/delete_recovery", methods=["POST"])
def api_delete_recovery():
    import db as _db
    data = request.get_json()
    _db.delete_recovery_log(data.get("date", ""))
    return jsonify({"ok": True})


# ── HealthKit ─────────────────────────────────────────────────

@wellness_bp.route("/api/healthkit_sync", methods=["POST"])
def api_healthkit_sync():
    """Importe les données HealthKit du jour — ne remplace pas les champs déjà remplis."""
    import db as _db
    from utils import _today_mtl
    data  = request.get_json() or {}
    today = _today_mtl()
    # Fetch existing entry for today
    logs     = _db.get_recovery_logs() or []
    existing = next((e for e in logs if e.get("date") == today), {})
    # Only fill in fields that are currently null
    entry = {
        "date":        today,
        "sleep_hours": existing.get("sleep_hours") or data.get("sleep_hours"),
        "resting_hr":  existing.get("resting_hr")  or data.get("resting_hr"),
        "hrv":         existing.get("hrv")          or data.get("hrv"),
        "steps":       existing.get("steps")        or data.get("steps"),
        "sleep_quality": existing.get("sleep_quality"),
        "soreness":    existing.get("soreness"),
        "notes":       existing.get("notes", ""),
    }
    if not any([entry["sleep_hours"], entry["resting_hr"], entry["hrv"], entry["steps"]]):
        return jsonify({"ok": False, "msg": "no data"})
    _db.upsert_recovery_log(entry)
    return jsonify({"ok": True})


# ── Health Dashboard ─────────────────────────────────────────

@wellness_bp.route("/api/health/daily_summary")
def api_health_daily_summary():
    """
    Résumé santé unifié pour un jour donné.
    ?date=YYYY-MM-DD  (défaut : aujourd'hui)
    """
    from health_data import get_daily_health_summary
    target_date = request.args.get("date")
    return jsonify(get_daily_health_summary(target_date))


@wellness_bp.route("/api/health/weekly_summary")
def api_health_weekly_summary():
    """
    Résumés des N derniers jours (du plus récent au plus ancien).
    ?days=7  (défaut : 7)
    """
    from health_data import get_weekly_health_summary
    try:
        days = int(request.args.get("days", 7))
        days = max(1, min(days, 90))
    except ValueError:
        days = 7
    return jsonify(get_weekly_health_summary(days))


# ── Life Stress Engine ────────────────────────────────────────

@wellness_bp.route("/api/life_stress/score")
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


@wellness_bp.route("/api/life_stress/trend")
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


# ── PSS — Perceived Stress Scale ─────────────────────────────

@wellness_bp.route("/api/pss/questions")
def api_pss_questions():
    """
    Retourne les questions PSS à afficher.
    ?short=true  → PSS-4 (4 questions, défaut : false)
    """
    from pss import get_questions
    is_short = request.args.get("short", "false").lower() == "true"
    return jsonify(get_questions(is_short))


@wellness_bp.route("/api/pss/submit", methods=["POST"])
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
        record = save_pss_record(
            responses       = [int(r) for r in responses],
            is_short        = bool(data.get("is_short", False)),
            notes           = data.get("notes"),
            triggers        = data.get("triggers"),
            trigger_ratings = data.get("trigger_ratings"),
        )
        return jsonify(record), 201
    except ValueError as e:
        return jsonify({"error": str(e)}), 422
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@wellness_bp.route("/api/pss/history")
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


@wellness_bp.route("/api/pss/check_due")
def api_pss_check_due():
    """
    Vérifie si un test PSS est dû.
    ?type=full|short  (défaut : full)
    """
    from pss import check_due as pss_check_due
    pss_type = request.args.get("type", "full")
    return jsonify(pss_check_due(pss_type))


@wellness_bp.route("/api/pss/delete", methods=["POST"])
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
        return jsonify({"success": True})
    except Exception:
        raise


# ── Sommeil ──────────────────────────────────────────────────

@wellness_bp.route("/api/sleep/log", methods=["POST"])
def api_sleep_log():
    from sleep import save_sleep_entry
    data = request.get_json() or {}
    bedtime   = data.get("bedtime")
    wake_time = data.get("wake_time")
    quality   = data.get("quality")
    if not bedtime or not wake_time or quality is None:
        return jsonify({"error": "bedtime, wake_time et quality requis"}), 400
    try:
        entry = save_sleep_entry(
            bedtime   = bedtime,
            wake_time = wake_time,
            quality   = int(quality),
            notes     = data.get("notes"),
        )
        return jsonify(entry)
    except Exception:
        raise

@wellness_bp.route("/api/sleep/history")
def api_sleep_history():
    from sleep import get_history as sleep_get_history
    try:
        limit  = int(request.args.get("limit", 20))
        offset = int(request.args.get("offset", 0))
    except ValueError:
        limit, offset = 20, 0
    return jsonify(sleep_get_history(limit, offset))

@wellness_bp.route("/api/sleep/today")
def api_sleep_today():
    from sleep import get_today as sleep_get_today
    entry = sleep_get_today()
    return jsonify(entry if entry else {})

@wellness_bp.route("/api/sleep/stats")
def api_sleep_stats():
    from sleep import get_stats as sleep_get_stats
    return jsonify(sleep_get_stats())

@wellness_bp.route("/api/sleep/delete", methods=["POST"])
def api_sleep_delete():
    from sleep import delete_entry as sleep_delete_entry
    data = request.get_json() or {}
    record_id = data.get("id")
    if not record_id:
        return jsonify({"error": "id requis"}), 400
    if sleep_delete_entry(record_id):
        return jsonify({"success": True})
    return jsonify({"error": "introuvable"}), 404


# ── Mood ─────────────────────────────────────────────────────

@wellness_bp.route("/api/mood/emotions")
def api_mood_emotions():
    from mood import EMOTIONS
    return jsonify(EMOTIONS)


@wellness_bp.route("/api/mood/log", methods=["POST"])
def api_mood_log():
    from mood import save_mood_entry
    data = request.get_json(silent=True) or {}
    score = data.get("score")
    if score is None:
        return jsonify({"error": "score requis (1-10)"}), 400
    try:
        entry = save_mood_entry(
            score    = int(score),
            emotions = data.get("emotions", []),
            notes    = data.get("notes"),
            triggers = data.get("triggers"),
        )
        return jsonify(entry), 201
    except ValueError as e:
        return jsonify({"error": str(e)}), 422


@wellness_bp.route("/api/mood/history")
def api_mood_history():
    from mood import get_history as mood_get_history
    try:
        days   = int(request.args.get("days", 90))
        limit  = int(request.args.get("limit", 20))
        offset = int(request.args.get("offset", 0))
    except ValueError:
        days, limit, offset = 90, 20, 0
    return jsonify(mood_get_history(days, limit, offset))


@wellness_bp.route("/api/mood/today")
def api_mood_today():
    from mood import get_today_entry as mood_today_entry
    entry = mood_today_entry()
    return jsonify(entry) if entry else jsonify(None)


@wellness_bp.route("/api/mood/check_due")
def api_mood_check_due():
    from mood import check_due as mood_check_due
    return jsonify(mood_check_due())


@wellness_bp.route("/api/mood/insights")
def api_mood_insights():
    from mood import generate_insights as mood_insights
    try:
        days = int(request.args.get("days", 30))
    except ValueError:
        days = 30
    return jsonify(mood_insights(days))


# ── Journal ──────────────────────────────────────────────────

@wellness_bp.route("/api/journal/today_prompt")
def api_journal_today_prompt():
    from journal import get_today_prompt
    return jsonify({"prompt": get_today_prompt()})


@wellness_bp.route("/api/journal/save", methods=["POST"])
def api_journal_save():
    from journal import save_entry as journal_save
    data = request.get_json(silent=True) or {}
    prompt     = data.get("prompt", "")
    content    = data.get("content", "")
    mood_score = data.get("mood_score")
    try:
        entry = journal_save(prompt, content, mood_score=mood_score)
        return jsonify(entry), 201
    except ValueError as e:
        return jsonify({"error": str(e)}), 422


@wellness_bp.route("/api/journal/entries")
def api_journal_entries():
    from journal import get_entries
    try:
        limit  = int(request.args.get("limit", 20))
        offset = int(request.args.get("offset", 0))
    except ValueError:
        limit, offset = 20, 0
    return jsonify(get_entries(limit, offset))


@wellness_bp.route("/api/journal/search")
def api_journal_search():
    from journal import search_entries
    q = request.args.get("q", "")
    return jsonify(search_entries(q))


# ── Breathwork ────────────────────────────────────────────────

@wellness_bp.route("/api/breathwork/techniques")
def api_breathwork_techniques():
    from breathwork import TECHNIQUES
    return jsonify(TECHNIQUES)


@wellness_bp.route("/api/breathwork/log", methods=["POST"])
def api_breathwork_log():
    from breathwork import log_session as bw_log
    data = request.get_json(silent=True) or {}
    technique_id = data.get("technique_id")
    if not technique_id:
        return jsonify({"error": "technique_id requis"}), 400
    try:
        session = bw_log(
            technique_id = technique_id,
            duration_sec = int(data.get("duration_sec", 0)),
            cycles       = int(data.get("cycles", 0)),
        )
        return jsonify(session), 201
    except ValueError as e:
        return jsonify({"error": str(e)}), 422


@wellness_bp.route("/api/breathwork/history")
def api_breathwork_history():
    from breathwork import get_history as bw_history
    try:
        days = int(request.args.get("days", 30))
    except ValueError:
        days = 30
    return jsonify(bw_history(days))


@wellness_bp.route("/api/breathwork/stats")
def api_breathwork_stats():
    from breathwork import get_stats as bw_stats_fn
    try:
        days = int(request.args.get("days", 7))
    except ValueError:
        days = 7
    return jsonify(bw_stats_fn(days))


# ── Self-Care Habits ──────────────────────────────────────────

@wellness_bp.route("/api/self_care/habits")
def api_self_care_habits():
    from self_care import get_habits
    return jsonify(get_habits())


@wellness_bp.route("/api/self_care/habits", methods=["POST"])
def api_self_care_habits_add():
    from self_care import add_habit
    data = request.get_json(silent=True) or {}
    name = data.get("name", "").strip()
    if not name:
        return jsonify({"error": "name requis"}), 400
    habit = add_habit(
        name     = name,
        icon     = data.get("icon", "star.fill"),
        category = data.get("category", "mental"),
    )
    return jsonify(habit), 201


@wellness_bp.route("/api/self_care/habits/<habit_id>", methods=["DELETE"])
def api_self_care_habits_delete(habit_id: str):
    from self_care import delete_habit
    deleted = delete_habit(habit_id)
    if not deleted:
        return jsonify({"error": "Habitude introuvable"}), 404
    return jsonify({"deleted": habit_id})


@wellness_bp.route("/api/self_care/log", methods=["POST"])
def api_self_care_log():
    from self_care import log_today as sc_log
    data = request.get_json(silent=True) or {}
    habit_ids = data.get("habit_ids", [])
    return jsonify(sc_log(habit_ids))


@wellness_bp.route("/api/self_care/today")
def api_self_care_today():
    from self_care import get_today_status
    return jsonify(get_today_status())


@wellness_bp.route("/api/self_care/streaks")
def api_self_care_streaks():
    from self_care import get_streaks
    return jsonify(get_streaks())


# ── Dashboard santé mentale ───────────────────────────────────

@wellness_bp.route("/api/mental_health/summary")
def api_mental_health_summary():
    from mental_health_dashboard import get_summary as mh_summary
    try:
        days = int(request.args.get("days", 7))
    except ValueError:
        days = 7
    return jsonify(mh_summary(days))
