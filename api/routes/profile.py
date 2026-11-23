from flask import Blueprint, jsonify, request
from werkzeug.utils import secure_filename
import logging

logger = logging.getLogger("trainingos")
profile_bp = Blueprint("profile", __name__)


@profile_bp.route("/api/profile", methods=["GET"])
def api_profile():
    import db as _db
    profile = _db.get_profile() or {}
    return jsonify(profile)


@profile_bp.route("/api/profil_data")
def api_profil_data():
    from body_weight import load_body_weight, get_tendance
    from user_profile import load_user_profile
    profile     = load_user_profile()
    body_weight = load_body_weight()
    tendance    = get_tendance(body_weight)
    legacy_weight_pending = bool(
        profile and profile.get("weight") and not body_weight
    )
    return jsonify({
        "profile":               profile,
        "body_weight":           body_weight,
        "tendance":              tendance,
        "legacy_weight_pending": legacy_weight_pending,
    })


@profile_bp.route("/api/profile_stats")
def api_profile_stats():
    """Lightweight profile stats — replaces the heavy stats_data call for ProfileView.

    Streak additif (2026-11) : ajout de weekly_streak_current / weekly_streak_best
    (source weekly_streaks.compute, même que grille Régularité et Stats). Les
    anciens champs current_streak / longest_streak (JOURS consécutifs, via
    get_session_streaks) restent pour les versions iOS installées qui les lisent
    encore — retirés dans un commit séparé après install du build qui consomme
    les nouveaux champs.
    """
    import db as _db
    from weekly_streaks import compute as _compute_weekly_streaks

    total_sessions   = _db.get_total_session_count()
    all_time_volume  = _db.get_all_time_volume_lbs()
    streaks          = _db.get_session_streaks()            # JOURS — déprécié
    weekly_streaks   = _compute_weekly_streaks()            # SEMAINES — source unique
    weekly_tonnage   = _db.get_weekly_tonnage(8)

    member_since = None
    try:
        if _db._client is not None:
            resp = (
                _db._client.table("workout_sessions")
                .select("date")
                .or_("completed.eq.true,rpe.not.is.null")
                .order("date")
                .limit(1)
                .execute()
            )
            if resp.data:
                member_since = resp.data[0].get("date")
    except Exception as e:
        logger.warning("profile_stats member_since query failed: %s", e)

    return jsonify({
        "total_sessions":        total_sessions,
        "all_time_volume_lbs":   all_time_volume,
        "current_streak":        streaks.get("current", 0),                       # JOURS — déprécié
        "longest_streak":        streaks.get("longest", 0),                       # JOURS — déprécié
        "weekly_streak_current": weekly_streaks.get("weekly_streak_current", 0),  # SEMAINES — nouveau
        "weekly_streak_best":    weekly_streaks.get("weekly_streak_best", 0),     # SEMAINES — nouveau
        "member_since":          member_since,
        "weekly_tonnage":        weekly_tonnage,
    })


@profile_bp.route("/api/update_profile", methods=["POST"])
def api_update_profile():
    from user_profile import load_user_profile, save_user_profile
    payload  = request.get_json(silent=True) or {}
    existing = load_user_profile()
    existing.update({k: v for k, v in payload.items() if v is not None})
    ok = save_user_profile(existing)
    if ok:
        if "sleep_goal_hours" in payload or "hrv_sensitivity" in payload:
            import readiness as _r
            _r._CACHE.clear()
        return jsonify({"success": True})
    return jsonify({"success": False, "error": "Erreur sauvegarde Supabase"}), 500


@profile_bp.route("/api/update_profile_photo", methods=["POST"])
def api_update_profile_photo():
    """Upload profile photo → Supabase Storage (bucket public 'profile-photos').

    Ordre : upload (nom non devinable user_1/<uuid>.<ext>) → écriture du profil
    {photo_url, photo_b64: None} → suppression de l'ancien fichier.
    Aucun repli base64 : un échec Storage ou profil est une erreur visible.
    Écriture du profil en échec → le nouveau fichier est supprimé (pas d'orphelin).
    Suppression de l'ancien en échec → journalisée, non bloquante.
    """
    import base64 as _b64
    import uuid
    from user_profile import load_user_profile, save_user_profile
    import db as _db

    data = request.get_json(silent=True) or {}
    data_url = data.get("photo_b64", "")  # nom du champ d'envoi, pas de stockage base64

    if not data_url or not data_url.startswith("data:image"):
        return jsonify({"success": False, "error": "Image invalide"}), 400

    if len(data_url) > 800_000:
        return jsonify({"success": False, "error": "Image trop lourde après compression"}), 400

    if _db._client is None:
        return jsonify({"success": False, "error": "storage_unavailable"}), 503

    header, b64_data = data_url.split(",", 1)
    content_type = header.split(";")[0].replace("data:", "")  # e.g. "image/jpeg"
    ext = {"image/jpeg": "jpg", "image/png": "png", "image/gif": "gif"}.get(content_type, "jpg")
    new_path = f"user_1/{uuid.uuid4()}.{ext}"
    bucket = _db._client.storage.from_(_PHOTO_BUCKET)

    try:
        bucket.upload(
            path=new_path,
            file=_b64.b64decode(b64_data),
            file_options={"content-type": content_type},
        )
        public_url = bucket.get_public_url(new_path).rstrip("?")
    except Exception as e:
        logger.warning("profile photo storage upload failed: %s", e)
        return jsonify({"success": False, "error": "storage_unavailable"}), 502

    old_path = _photo_path_from_url(load_user_profile().get("photo_url"))

    if not save_user_profile({"photo_url": public_url, "photo_b64": None}):
        try:
            bucket.remove([new_path])
        except Exception as e:
            logger.warning("profile photo orphan cleanup failed for %s: %s", new_path, e)
        return jsonify({"success": False, "error": "profile_save_failed"}), 500

    if old_path and old_path != new_path:
        try:
            bucket.remove([old_path])
        except Exception as e:
            logger.warning("profile photo old file delete failed for %s: %s", old_path, e)

    return jsonify({"success": True, "photo_url": public_url})


_PHOTO_BUCKET = "profile-photos"


def _photo_path_from_url(url):
    """Chemin bucket d'une URL publique profile-photos, limité à user_1/. Sinon None."""
    if not url or f"/{_PHOTO_BUCKET}/" not in url:
        return None
    path = url.split(f"/{_PHOTO_BUCKET}/", 1)[1].split("?", 1)[0]
    return path if path.startswith("user_1/") else None
