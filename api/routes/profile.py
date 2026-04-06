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
    existing.update({k: v for k, v in request.json.items() if v is not None})
    ok = save_user_profile(existing)
    if ok:
        return jsonify({"success": True})
    return jsonify({"success": False, "error": "Erreur sauvegarde Supabase"}), 500


@profile_bp.route("/api/update_profile_photo", methods=["POST"])
def api_update_profile_photo():
    from user_profile import load_user_profile, save_user_profile
    # Reçoit du JSON avec photo_b64 déjà compressée/redimensionnée côté client
    data = request.get_json(silent=True) or {}
    data_url = data.get("photo_b64", "")

    if not data_url or not data_url.startswith("data:image"):
        return jsonify({"success": False, "error": "Image invalide"}), 400

    # Vérifie la taille (~600KB max en base64 = ~450KB image)
    if len(data_url) > 800_000:
        return jsonify({"success": False, "error": "Image trop lourde après compression"}), 400

    profile = load_user_profile()
    profile["photo_b64"] = data_url
    profile.pop("photo", None)
    ok = save_user_profile(profile)

    if ok:
        return jsonify({"success": True})
    return jsonify({"success": False, "error": "Erreur sauvegarde"}), 500
