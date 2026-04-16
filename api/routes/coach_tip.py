from flask import Blueprint, jsonify
import logging, os, json as _json
from datetime import date

logger = logging.getLogger("trainingos")

coach_tip_bp = Blueprint("coach_tip", __name__)


def _gather_context() -> str:
    """Collect lightweight signals from DB for today's tip."""
    import db as _db
    lines: list[str] = []

    # --- Last session ---
    try:
        sessions = _db.get_workout_sessions(limit=3)
        if sessions:
            last = sessions[0]
            lines.append(
                f"Dernière séance: {last.get('date','?')} — "
                f"RPE {last.get('rpe','?')}/10, "
                f"nom: {last.get('session_name') or last.get('session_type','?')}"
            )
    except Exception:
        pass

    # --- Nutrition (3 derniers jours) ---
    try:
        nutrition = _db.get_nutrition_entries_recent(n=3)
        if nutrition:
            cals  = [d.get("calories", 0) or 0 for d in nutrition]
            prots = [d.get("proteines", 0) or 0 for d in nutrition]
            avg_cal  = round(sum(cals)  / len(cals))
            avg_prot = round(sum(prots) / len(prots))
            lines.append(f"Nutrition (moy. 3j): {avg_cal} kcal, {avg_prot}g protéines")
    except Exception:
        pass

    # --- Recovery (2 derniers jours) ---
    try:
        recovery = _db.get_recovery_logs(limit=2)
        if recovery:
            r = recovery[0]
            parts = []
            if r.get("sleep_hours") is not None:
                parts.append(f"sommeil {r['sleep_hours']}h")
            if r.get("hrv") is not None:
                parts.append(f"HRV {r['hrv']} ms")
            if r.get("resting_hr") is not None:
                parts.append(f"FC repos {r['resting_hr']} bpm")
            if r.get("soreness") is not None:
                parts.append(f"douleur {r['soreness']}/10")
            if r.get("steps") is not None:
                parts.append(f"{r['steps']} pas")
            if parts:
                lines.append("Récupération: " + ", ".join(parts))
    except Exception:
        pass

    # --- Profile ---
    try:
        profile = _db.get_profile()
        if profile:
            info = []
            if profile.get("weight"):
                info.append(f"poids {profile['weight']} lbs")
            if profile.get("goal"):
                info.append(f"objectif: {profile['goal']}")
            if info:
                lines.append("Profil: " + ", ".join(info))
    except Exception:
        pass

    return "\n".join(lines) if lines else "Données insuffisantes."


@coach_tip_bp.route("/api/coach/daily_tip", methods=["GET"])
def api_daily_tip():
    import anthropic as _anthropic

    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not api_key:
        return jsonify({"error": "ANTHROPIC_API_KEY manquant"}), 500

    today = date.today().isoformat()
    context = _gather_context()
    logger.info("Coach tip — date=%s context_len=%d", today, len(context))

    try:
        client = _anthropic.Anthropic(api_key=api_key)
        message = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=300,
            system=(
                "Tu es un coach sportif expert. "
                "À partir des données d'un athlète, génère UN conseil du jour personnalisé, court et actionnable. "
                "Réponds UNIQUEMENT avec un objet JSON valide (pas de texte autour) au format exact :\n"
                '{"title": "titre court (max 6 mots)", "body": "conseil en 1-2 phrases max", '
                '"domain": "nutrition|training|recovery|sleep"}\n'
                "Le domain doit correspondre au sujet principal du conseil. "
                "Utilise le tutoiement. Réponds en français."
            ),
            messages=[{"role": "user", "content": f"Données athlète du {today}:\n{context}"}],
        )
        raw = message.content[0].text.strip()
        # Extract JSON object
        start = raw.find("{")
        end = raw.rfind("}") + 1
        if start == -1 or end == 0:
            return jsonify({"error": "Réponse non structurée", "raw": raw}), 500
        tip = _json.loads(raw[start:end])
        return jsonify(tip)
    except Exception:
        raise
