from flask import Blueprint, jsonify
from datetime import datetime, timezone
import logging
import json
import os

logger = logging.getLogger("trainingos")
daily_brief_bp = Blueprint("daily_brief", __name__)


def _check_triggers(brief_data: dict) -> dict:
    """Return active trigger flags from morning_brief data."""
    flags = brief_data.get("flags", {})
    rec = brief_data.get("recommendation", "go")
    streak = brief_data.get("phoenix_streak", 0)
    return {
        "recovery_needed": rec in ("reduce", "defer") or flags.get("hrv_drop") or flags.get("sleep_deprivation") or flags.get("training_overload"),
        "momentum": streak >= 14 and rec == "go",
    }


def _build_context(brief_data: dict) -> str:
    """Compose a compact context string for Claude from morning_brief data."""
    lss = brief_data.get("lss")
    rec = brief_data.get("recommendation", "go")
    session = brief_data.get("session_today", "")
    intensity = brief_data.get("session_intensity", "")
    adjustments = brief_data.get("adjustments", [])
    flags = brief_data.get("flags", {})
    streak = brief_data.get("phoenix_streak", 0)

    lines = [f"Session du jour: {session} ({intensity})"]
    if lss is not None:
        lines.append(f"Readiness (LSS): {lss}/100 — {rec}")
    if flags.get("hrv_drop"):
        lines.append("Signal: HRV en baisse")
    if flags.get("sleep_deprivation"):
        lines.append("Signal: sommeil insuffisant")
    if flags.get("training_overload"):
        lines.append("Signal: surcharge cumulée")
    if adjustments:
        lines.append("Ajustements: " + " | ".join(adjustments))
    if streak >= 7:
        lines.append(f"Phoenix streak: {streak} jours")

    return "\n".join(lines)


def _build_fallback_brief(brief_data: dict) -> dict:
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

    return {"use_quote": True, "mot": None, "lecture": lecture, "recommandation": reco}


def _call_claude(context: str, triggers: dict) -> dict:
    """Call Claude once and return parsed brief dict."""
    import anthropic as _anthropic

    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not api_key:
        raise RuntimeError("ANTHROPIC_API_KEY manquant")

    trigger_note = ""
    if triggers.get("recovery_needed"):
        trigger_note = "TRIGGER ACTIF: récupération — oriente le mot vers la récupération/patience si use_quote=false."
    elif triggers.get("momentum"):
        trigger_note = "TRIGGER ACTIF: momentum — oriente le mot vers la constance/lancée si use_quote=false."

    system = (
        "Tu es le coach de performance de Vincent — gym et vie. "
        "Tu parles directement à lui, au présent, sans flatterie."
    )

    user_msg = (
        f"CONTEXTE:\n{context}\n\n"
        f"{trigger_note}\n\n"
        "Génère un objet JSON avec exactement ces champs:\n"
        '- "use_quote": true (utilise citation statique) ou false (génère un mot contextuel)\n'
        '- "mot": null si use_quote=true, sinon une phrase de coaching max 20 mots\n'
        '- "lecture": 2 phrases — ce que tu vois dans les chiffres (max 50 mots, langage humain, pas de métaphores)\n'
        '- "recommandation": liste de 1-2 strings, chaque action max 10 mots, commencer par un verbe\n\n'
        "Règles:\n"
        "- use_quote=false SEULEMENT si trigger actif\n"
        "- lecture = chiffres traduits en implications concrètes\n"
        "- recommandation = verbe + action (ex: \"Plafonne à 8 RPE ce soir\")\n"
        "- Réponds UNIQUEMENT avec le JSON, sans markdown ni texte autour."
    )

    client = _anthropic.Anthropic(api_key=api_key)
    message = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=200,
        system=system,
        messages=[{"role": "user", "content": user_msg}],
    )

    raw = message.content[0].text.strip()
    return json.loads(raw)


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
        triggers = _check_triggers(brief_data)
        context = _build_context(brief_data)

        try:
            result = _call_claude(context, triggers)
        except Exception as claude_err:
            logger.warning("daily_brief Claude call failed, using fallback: %s", claude_err)
            result = _build_fallback_brief(brief_data)

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
