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
    """Lightweight profile stats — replaces the heavy stats_data call for ProfileView."""
    import db as _db

    total_sessions  = _db.get_total_session_count()
    all_time_volume = _db.get_all_time_volume_lbs()
    streaks         = _db.get_session_streaks()
    weekly_tonnage  = _db.get_weekly_tonnage(8)

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
        "total_sessions":      total_sessions,
        "all_time_volume_lbs": all_time_volume,
        "current_streak":      streaks.get("current", 0),
        "longest_streak":      streaks.get("longest", 0),
        "member_since":        member_since,
        "weekly_tonnage":      weekly_tonnage,
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
        from routes.daily_brief import invalidate_cache as _brief_invalidate
        _brief_invalidate()
        return jsonify({"success": True})
    return jsonify({"success": False, "error": "Erreur sauvegarde Supabase"}), 500


@profile_bp.route("/api/update_profile_photo", methods=["POST"])
def api_update_profile_photo():
    """Upload profile photo.
    Tries Supabase Storage first (returns a public URL stored in photo_url).
    Falls back to base64 in photo_b64 if Storage is unavailable.
    Bucket: 'profile-photos' (must be created in Supabase dashboard, public access).
    """
    import base64 as _b64
    from user_profile import load_user_profile, save_user_profile
    import db as _db

    data = request.get_json(silent=True) or {}
    data_url = data.get("photo_b64", "")

    if not data_url or not data_url.startswith("data:image"):
        return jsonify({"success": False, "error": "Image invalide"}), 400

    if len(data_url) > 800_000:
        return jsonify({"success": False, "error": "Image trop lourde après compression"}), 400

    profile = load_user_profile()

    # Try Supabase Storage upload → store URL instead of base64
    try:
        if _db._client is not None:
            # Decode base64 part: "data:image/jpeg;base64,<data>"
            header, b64_data = data_url.split(",", 1)
            content_type = header.split(";")[0].replace("data:", "")  # e.g. "image/jpeg"
            ext = {"image/jpeg": "jpg", "image/png": "png", "image/gif": "gif"}.get(content_type, "jpg")
            image_bytes = _b64.b64decode(b64_data)
            file_path = f"user_1/profile.{ext}"

            # Upload (upsert — overwrite previous)
            _db._client.storage.from_("profile-photos").upload(
                path=file_path,
                file=image_bytes,
                file_options={"content-type": content_type, "upsert": "true"},
            )
            public_url = _db._client.storage.from_("profile-photos").get_public_url(file_path)

            profile["photo_url"] = public_url
            profile.pop("photo_b64", None)
            ok = save_user_profile(profile)
            if ok:
                return jsonify({"success": True, "photo_url": public_url})
    except Exception as e:
        import logging as _logging
        _logging.getLogger("trainingos").warning("Photo Storage upload failed, falling back to base64: %s", e)

    # Fallback: store base64 directly
    profile["photo_b64"] = data_url
    ok = save_user_profile(profile)
    if ok:
        return jsonify({"success": True})
    return jsonify({"success": False, "error": "Erreur sauvegarde"}), 500
