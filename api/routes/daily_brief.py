from flask import Blueprint, jsonify
from datetime import datetime, timezone
import logging

logger = logging.getLogger("trainingos")
daily_brief_bp = Blueprint("daily_brief", __name__)


def _build_brief(brief_data: dict) -> dict:
    """Generate a brief from morning_brief data without calling Claude."""
    rec = brief_data.get("recommendation", "go")
    adjustments = brief_data.get("adjustments", [])
    session = brief_data.get("session_today", "")
    lss = brief_data.get("lss")
    flags = brief_data.get("flags", {})

    parts = []
    if lss is not None:
        parts.append(f"Readiness à {lss}/100 aujourd'hui.")
    if flags.get("hrv_drop"):
        parts.append("HRV en baisse — évite les efforts maximaux.")
    elif flags.get("sleep_deprivation"):
        parts.append("Sommeil insuffisant — réduis l'intensité.")
    elif flags.get("training_overload"):
        parts.append("Surcharge cumulée — déload recommandé.")
    elif rec == "go":
        parts.append("Paramètres dans la norme — séance sans contrainte.")
    lecture = " ".join(parts) or "Données en cours de chargement."

    reco = adjustments[:2] if adjustments else ([f"Séance {session} prévue."] if session else ["Bonne séance."])
    if flags.get("hrv_drop") or flags.get("sleep_deprivation"):
        reco.append("Ce soir : fais ta routine du soir")

    return {"use_quote": True, "mot": None, "lecture": lecture, "recommandation": reco}


@daily_brief_bp.route("/api/coach/daily_brief", methods=["GET"])
def get_daily_brief():
    """Return (or generate) the daily coaching brief. Cached once per day per user."""
    from utils import _today_mtl

    today = _today_mtl()

    # Check DB cache first
    try:
        import db as _db
        if _db._client:
            cached = _db._client.table("daily_brief") \
                .select("use_quote,mot,lecture,recommandation,generated_at,date") \
                .eq("date", today) \
                .maybe_single() \
                .execute()
            if cached.data:
                row = cached.data
                return jsonify({
                    "date":           row["date"],
                    "use_quote":      row["use_quote"],
                    "mot":            row.get("mot"),
                    "lecture":        row["lecture"],
                    "recommandation": row["recommandation"],
                    "generated_at":   row["generated_at"],
                    "cached":         True,
                })
    except Exception as e:
        logger.warning("daily_brief cache read failed: %s", e)

    # Generate brief
    try:
        from morning_brief import get_morning_brief
        brief_data = get_morning_brief()
        result = _build_brief(brief_data)

        use_quote = bool(result.get("use_quote", True))
        mot = None if use_quote else (result.get("mot") or None)
        lecture = str(result.get("lecture", ""))
        recommandation = result.get("recommandation", [])
        if not isinstance(recommandation, list):
            recommandation = [str(recommandation)]

        # Store in DB
        try:
            import db as _db
            if _db._client:
                _db._client.table("daily_brief").upsert({
                    "date":           today,
                    "use_quote":      use_quote,
                    "mot":            mot,
                    "lecture":        lecture,
                    "recommandation": recommandation,
                    "generated_at":   datetime.now(timezone.utc).isoformat(),
                }, on_conflict="date").execute()
        except Exception as e:
            logger.warning("daily_brief cache write failed: %s", e)

        return jsonify({
            "date":           today,
            "use_quote":      use_quote,
            "mot":            mot,
            "lecture":        lecture,
            "recommandation": recommandation,
            "generated_at":   datetime.now(timezone.utc).isoformat(),
            "cached":         False,
        })

    except Exception as e:
        logger.error("daily_brief generation failed: %s", e)
        return jsonify({"error": str(e)}), 500
