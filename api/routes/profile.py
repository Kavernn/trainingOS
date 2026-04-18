from flask import Blueprint, jsonify, request
from werkzeug.utils import secure_filename

profile_bp = Blueprint("profile", __name__)


@profile_bp.route("/api/profil_data")
def api_profil_data():
    from body_weight import load_body_weight, get_tendance
    from user_profile import load_user_profile
    profile     = load_user_profile()
    body_weight = load_body_weight()
    tendance    = get_tendance(body_weight)
    return jsonify({
        "profile":     profile,
        "body_weight": body_weight,
        "tendance":    tendance,
    })


@profile_bp.route("/api/update_profile", methods=["POST"])
def api_update_profile():
    from user_profile import load_user_profile, save_user_profile
    existing = load_user_profile()
    existing.update({k: v for k, v in (request.get_json(silent=True) or {}).items() if v is not None})
    ok = save_user_profile(existing)
    if ok:
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
    except Exception:
        pass  # Storage not configured — fall back to base64

    # Fallback: store base64 directly
    profile["photo_b64"] = data_url
    ok = save_user_profile(profile)
    if ok:
        return jsonify({"success": True})
    return jsonify({"success": False, "error": "Erreur sauvegarde"}), 500
