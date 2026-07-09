from flask import Blueprint, jsonify, request
from datetime import date
from utils import _today_mtl

wellness_recovery_bp = Blueprint("wellness_recovery", __name__)


@wellness_recovery_bp.route("/api/cardio_data")
def api_cardio_data():
    import db as _db
    log = _db.get_cardio_logs() or []
    return jsonify({"cardio_log": sorted(log, key=lambda x: x.get("date", ""), reverse=True)})

@wellness_recovery_bp.route("/api/log_cardio", methods=["POST"])
def api_log_cardio():
    import db as _db
    data = request.get_json(silent=True) or {}
    raw_dur = data.get("duration_min")
    raw_pace_s = data.get("pace_avg_seconds")
    entry = {
        "date":             data.get("date", _today_mtl()),
        "type":             data.get("type", "course"),
        "duration_min":     int(raw_dur) if raw_dur is not None else None,
        "distance_km":      data.get("distance_km"),
        "avg_pace":         data.get("avg_pace"),
        "avg_hr":           data.get("avg_hr"),
        "cadence":          data.get("cadence"),
        "calories":         data.get("calories"),
        "rpe":              data.get("rpe"),
        "notes":            data.get("notes", ""),
        "start_time":       data.get("start_time"),
        "end_time":         data.get("end_time"),
        "pace_avg_seconds": int(raw_pace_s) if raw_pace_s is not None else None,
        "gps_points":       data.get("gps_points"),
        "route_encoded":    data.get("route_encoded"),
        "coach_note":       data.get("coach_note"),
    }
    # Strip None values — don't overwrite existing columns with nulls
    entry = {k: v for k, v in entry.items() if v is not None}
    _db.insert_cardio_log(entry)
    return jsonify({"ok": True})

@wellness_recovery_bp.route("/api/delete_cardio", methods=["POST"])
def api_delete_cardio():
    import db as _db
    data = request.get_json(silent=True) or {}
    _db.delete_cardio_log(data.get("date", ""), data.get("type", ""))
    return jsonify({"ok": True})


@wellness_recovery_bp.route("/api/recovery_data")
def api_recovery_data():
    import db as _db
    log = _db.get_recovery_logs() or []
    return jsonify({"recovery_log": sorted(log, key=lambda x: x.get("date", ""), reverse=True)})

@wellness_recovery_bp.route("/api/log_recovery", methods=["POST"])
def api_log_recovery():
    # Merge par présence : un champ ABSENT du POST préserve l'existant en DB.
    # Un champ PRÉSENT (même à None) écrit la nouvelle valeur.
    # Sans ce merge, `.upsert()` brut écrit NULL sur les colonnes absentes du payload —
    # même piège que sets_json. Pattern inspiré d'api_healthkit_sync.
    import db as _db
    data     = request.get_json(silent=True) or {}
    date     = data.get("date", _today_mtl())
    logs     = _db.get_recovery_logs() or []
    existing = next((e for e in logs if e.get("date") == date), {})

    merged = dict(existing)
    merged["date"] = date

    MERGEABLE = (
        "sleep_hours", "resting_hr", "hrv",
        "steps", "active_energy",
        "hr_morning", "hr_post_workout", "hr_evening",
        "bedtime", "wake_time",
    )
    for field in MERGEABLE:
        if field in data:
            merged[field] = data[field]

    # CHECK constraint safeguards — colonnes 1-10 : 0 = non renseigné → NULL.
    # fatigue_perceived n'a pas de CHECK (migration 038) : accepte 0.
    if "sleep_quality" in data:
        v = data["sleep_quality"]; merged["sleep_quality"] = v if v else None
    if "soreness" in data:
        v = data["soreness"]; merged["soreness"] = v if v else None
    if "energy_pre" in data:
        v = data["energy_pre"]; merged["energy_pre"] = v if v else None
    if "fatigue_perceived" in data:
        v = data["fatigue_perceived"]; merged["fatigue_perceived"] = v if v is not None else None

    # Notes : préserver l'existante si le POST envoie une note vide
    # (cohérent avec la sémantique "champ absent" — pour effacer, UI dédiée).
    if data.get("notes"):
        merged["notes"] = data["notes"]

    # Toute écriture via cet endpoint = saisie utilisateur → manual > healthkit.
    merged["source"] = "manual"

    ok = _db.upsert_recovery_log(merged)
    if not ok:
        return jsonify({"error": "Erreur base de données"}), 500
    import readiness as _readiness
    _readiness.invalidate_cache()
    return jsonify({"ok": True})

@wellness_recovery_bp.route("/api/delete_recovery", methods=["POST"])
def api_delete_recovery():
    import db as _db
    data = request.get_json(silent=True) or {}
    _db.delete_recovery_log(data.get("date", ""))
    import readiness as _readiness
    _readiness.invalidate_cache()
    return jsonify({"ok": True})


@wellness_recovery_bp.route("/api/healthkit_sync", methods=["POST"])
def api_healthkit_sync():
    """
    Importe les données HealthKit du jour.
    Règle merge : manual > HK si les deux existent.
    Retourne l'entrée finale après merge.

    Champs HK acceptés :
      sleep_hours, resting_hr, hrv, steps,
      active_energy, hr_morning, hr_post_workout, hr_evening

    Champs manuels préservés (jamais écrasés par HK) :
      sleep_quality, soreness, fatigue_perceived, energy_pre, notes
    """
    import db as _db
    data     = request.get_json() or {}
    today    = _today_mtl()
    logs     = _db.get_recovery_logs() or []
    existing = next((e for e in logs if e.get("date") == today), {})
    is_manual = existing.get("source") == "manual"

    def _hk(field):
        """Merge rule : valeur manuelle existante > nouvelle valeur HK."""
        if is_manual and existing.get(field) is not None:
            return existing.get(field)
        incoming = data.get(field)
        return incoming if incoming is not None else existing.get(field)

    entry = {
        "date":              today,
        # Champs HK — règle manual > HK
        "sleep_hours":       _hk("sleep_hours"),
        "resting_hr":        _hk("resting_hr"),
        "hrv":               _hk("hrv"),
        "steps":             _hk("steps"),
        "active_energy":     _hk("active_energy"),
        "hr_morning":        _hk("hr_morning"),
        "hr_post_workout":   _hk("hr_post_workout"),
        "hr_evening":        _hk("hr_evening"),
        # Champs manuels — toujours préservés
        "sleep_quality":     existing.get("sleep_quality"),
        "soreness":          existing.get("soreness"),
        "fatigue_perceived": existing.get("fatigue_perceived"),
        "energy_pre":        existing.get("energy_pre"),
        "notes":             existing.get("notes", ""),
        "bedtime":           existing.get("bedtime"),
        "wake_time":         existing.get("wake_time"),
        "source":            existing.get("source") or "healthkit",
    }

    hk_fields = ["sleep_hours", "resting_hr", "hrv", "steps",
                 "active_energy", "hr_morning", "hr_post_workout", "hr_evening"]
    if not any(entry.get(f) for f in hk_fields):
        return jsonify({"ok": False, "msg": "no data"})

    ok = _db.upsert_recovery_log(entry)
    if not ok:
        return jsonify({"error": "Erreur base de données"}), 500

    import readiness as _readiness
    _readiness.invalidate_cache()
    return jsonify({"ok": True, "entry": entry})


@wellness_recovery_bp.route("/api/health/daily_summary")
def api_health_daily_summary():
    """
    Résumé santé unifié pour un jour donné.
    ?date=YYYY-MM-DD  (défaut : aujourd'hui)
    """
    from health_data import get_daily_health_summary
    target_date = request.args.get("date")
    return jsonify(get_daily_health_summary(target_date))


@wellness_recovery_bp.route("/api/health/weekly_summary")
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
