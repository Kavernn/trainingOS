from flask import Blueprint, jsonify, request
import logging
from utils import _today_mtl

logger = logging.getLogger("trainingos")
body_weight_bp = Blueprint("body_weight", __name__)


@body_weight_bp.route("/api/body_weight", methods=["GET", "POST"])
def api_body_weight():
    if request.method == "GET":
        import db as _db
        try:
            limit = int(request.args.get("limit", 100))
        except ValueError:
            limit = 100
        logs = _db.get_body_weight_logs(limit=limit) or []
        return jsonify(logs)

    from body_weight import log_body_weight
    data      = request.get_json(silent=True) or {}
    poids     = float(data.get("poids", 0))
    note      = data.get("note", "")
    body_fat  = float(data.get("body_fat"))  if data.get("body_fat")  is not None else None
    waist_cm  = float(data.get("waist_cm"))  if data.get("waist_cm")  is not None else None
    neck_cm   = float(data.get("neck_cm"))   if data.get("neck_cm")   is not None else None
    arms_cm   = float(data.get("arms_cm"))   if data.get("arms_cm")   is not None else None
    chest_cm  = float(data.get("chest_cm"))  if data.get("chest_cm")  is not None else None
    thighs_cm = float(data.get("thighs_cm")) if data.get("thighs_cm") is not None else None
    hips_cm   = float(data.get("hips_cm"))   if data.get("hips_cm")   is not None else None

    if not poids or not (80 <= poids <= 500):
        return jsonify({"error": "Poids invalide (80–500 lbs)"}), 400
    if body_fat is not None and not (3 <= body_fat <= 60):
        return jsonify({"error": "body_fat invalide (3–60%)"}), 400
    for label, val in [("waist_cm", waist_cm), ("neck_cm", neck_cm), ("arms_cm", arms_cm),
                       ("chest_cm", chest_cm), ("thighs_cm", thighs_cm), ("hips_cm", hips_cm)]:
        if val is not None and not (20 <= val <= 250):
            return jsonify({"error": f"{label} invalide (20–250 cm)"}), 400

    log_body_weight(poids, note, body_fat, waist_cm, neck_cm, arms_cm, chest_cm, thighs_cm, hips_cm)
    return jsonify({"success": True, "poids": poids})


@body_weight_bp.route("/api/body_weight/update", methods=["POST"])
def api_update_body_weight():
    import db as _db
    data        = request.get_json(silent=True) or {}
    target_date = data.get("date", "")
    new_poids   = float(data.get("poids", 0))
    body_fat    = float(data.get("body_fat")) if data.get("body_fat") is not None else None
    note        = data.get("note", "")
    waist_cm    = float(data.get("waist_cm"))  if data.get("waist_cm")  is not None else None
    neck_cm     = float(data.get("neck_cm"))   if data.get("neck_cm")   is not None else None
    arms_cm     = float(data.get("arms_cm"))   if data.get("arms_cm")   is not None else None
    chest_cm    = float(data.get("chest_cm"))  if data.get("chest_cm")  is not None else None
    thighs_cm   = float(data.get("thighs_cm")) if data.get("thighs_cm") is not None else None
    hips_cm     = float(data.get("hips_cm"))   if data.get("hips_cm")   is not None else None

    if not target_date or not ("2020-01-01" <= target_date <= _today_mtl()):
        return jsonify({"error": "date invalide"}), 400
    if not new_poids or not (80 <= new_poids <= 500):
        return jsonify({"error": "Poids invalide (80–500 lbs)"}), 400
    if body_fat is not None and not (3 <= body_fat <= 60):
        return jsonify({"error": "body_fat invalide (3–60%)"}), 400
    for label, val in [("waist_cm", waist_cm), ("neck_cm", neck_cm), ("arms_cm", arms_cm),
                       ("chest_cm", chest_cm), ("thighs_cm", thighs_cm), ("hips_cm", hips_cm)]:
        if val is not None and not (20 <= val <= 250):
            return jsonify({"error": f"{label} invalide (20–250 cm)"}), 400

    ok = _db.upsert_body_weight(
        target_date, new_poids, note=note,
        body_fat=body_fat, waist_cm=waist_cm, neck_cm=neck_cm, arms_cm=arms_cm,
        chest_cm=chest_cm, thighs_cm=thighs_cm, hips_cm=hips_cm,
    )
    if not ok:
        return jsonify({"success": False, "error": "Entrée introuvable"}), 404
    return jsonify({"success": True})


@body_weight_bp.route("/api/body_weight/delete", methods=["POST"])
def api_delete_body_weight():
    import db as _db
    data  = request.get_json(silent=True) or {}
    ok = _db.delete_body_weight(data.get("date", ""))
    if not ok:
        return jsonify({"success": False, "error": "Entrée introuvable"}), 404
    return jsonify({"success": True})
