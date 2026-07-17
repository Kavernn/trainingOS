"""GET /api/readiness — Pre-session readiness score."""
from flask import Blueprint, jsonify, request
import readiness as _r

readiness_bp = Blueprint("readiness", __name__)


@readiness_bp.route("/api/readiness", methods=["GET"])
def api_readiness():
    # Le fantôme {score:65} sur except a été supprimé de compute() — l'échec
    # de calcul remonte et devient un HTTP 500 explicite. Message générique
    # côté client (pas de fuite d'infra), détail complet logué serveur-side
    # par compute() via logger.exception.
    try:
        return jsonify(_r.compute())
    except Exception:
        return jsonify({"error": "readiness compute failed", "reason": "compute_error"}), 500


@readiness_bp.route("/api/readiness/history", methods=["GET"])
def api_readiness_history():
    """Return historical readiness scores as [{date, score}, ...].

    Lecture pure — pas de recalcul, pas d'écriture, pas de backfill.
    Query param `days` par défaut 14, clampé [1, 90].
    """
    import db as _db
    try:
        days = int(request.args.get("days", 14))
    except (TypeError, ValueError):
        days = 14
    days = max(1, min(days, 90))
    history = _db.get_readiness_history(days=days) or []
    return jsonify({"history": history})
