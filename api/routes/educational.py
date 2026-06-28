from flask import Blueprint, jsonify, request
import logging

logger = logging.getLogger("trainingos")
educational_bp = Blueprint("educational", __name__)


@educational_bp.route("/api/educational/content", methods=["GET"])
def get_educational_content():
    """Return educational capsules filtered by category / exercise_id / movement_pattern / muscle_specific.

    Query params (tous optionnels):
      - category : kine | anatomie | sports_science | well_being | nutrition
      - exercise_id : uuid
      - movement_pattern : valeur prod réelle (Title Case anglais, ex: "Horizontal Push")
      - muscle_specific : valeur prod réelle (français, ex: "Grand dorsal")
      - limit : 1..100 (défaut 20)
    """
    try:
        import db as _db
        if _db._client is None:
            return jsonify([])

        try:
            limit = int(request.args.get("limit", "20"))
        except ValueError:
            limit = 20
        limit = max(1, min(limit, 100))

        q = _db._client.table("educational_content").select(
            "id, category, title, body, exercise_id, movement_pattern, muscle_specific, tags, created_at"
        )

        if c := request.args.get("category"):
            q = q.eq("category", c)
        if eid := request.args.get("exercise_id"):
            q = q.eq("exercise_id", eid)
        if mp := request.args.get("movement_pattern"):
            q = q.eq("movement_pattern", mp)
        if ms := request.args.get("muscle_specific"):
            q = q.eq("muscle_specific", ms)

        resp = q.order("created_at", desc=True).limit(limit).execute()
        return jsonify(resp.data or [])

    except Exception as e:
        logger.error("educational_content fetch failed: %s", e)
        return jsonify({"error": str(e)}), 500
