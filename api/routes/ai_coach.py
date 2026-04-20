from flask import Blueprint, jsonify, request
import logging

logger = logging.getLogger("trainingos")

ai_coach_bp = Blueprint("ai_coach", __name__)


@ai_coach_bp.route("/api/ai/propose", methods=["POST"])
def api_ai_propose():
    """Claude returns structured program modification proposals as JSON."""
    from utils import _ai_rate_check, _AI_TOKENS
    if not _ai_rate_check():
        return jsonify({"error": "Trop de requêtes — réessaie dans quelques minutes."}), 429
    import os, json as _json
    import anthropic as _anthropic
    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not api_key:
        return jsonify({"error": "ANTHROPIC_API_KEY manquant"}), 500
    try:
        data    = request.get_json(silent=True) or {}
        context = data.get("context", "")
        if not context:
            return jsonify({"error": "Contexte manquant"}), 400

        logger.info("Claude propose — context_len=%d", len(context))
        client  = _anthropic.Anthropic(api_key=api_key)
        message = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=1500,
            system=(
                "Tu es un coach expert en programmation musculaire. "
                "Tu reçois des données d'entraînement et tu proposes des modifications concrètes au programme. "
                "Tu DOIS répondre UNIQUEMENT avec un tableau JSON valide, sans texte avant ni après. "
                "Format exact de chaque proposition:\n"
                '{"jour": "Nom du jour/session", "action": "add|remove|replace|scheme", '
                '"exercise": "nom (pour add)", "old_exercise": "nom (pour remove/replace)", '
                '"new_exercise": "nom (pour replace)", "scheme": "ex: 3x8-10", '
                '"reason": "explication courte en français"}\n'
                "Propose 3 à 6 modifications pertinentes basées sur les données. "
                "Ne compare jamais le volume brut entre muscles — utilise les sets. "
                "La surcharge progressive inclut l'augmentation des reps ET du poids : "
                "8×15 lbs > 6×15 lbs est du vrai progrès — tiens-en compte dans tes recommandations."
            ),
            messages=[{"role": "user", "content": context}]
        )
        raw = message.content[0].text.strip()
        # Extract JSON array from response
        start = raw.find('[')
        end   = raw.rfind(']') + 1
        if start == -1 or end == 0:
            return jsonify({"error": "Réponse non structurée", "raw": raw}), 500
        try:
            proposals = _json.loads(raw[start:end])
        except _json.JSONDecodeError as e:
            logger.error("ai/propose JSON decode error: %s — raw=%s", e, raw[:200])
            return jsonify({"error": "Réponse non structurée du modèle"}), 500
        return jsonify({"proposals": proposals})
    except Exception:
        raise


@ai_coach_bp.route("/api/ai/narrative", methods=["POST"])
def api_ai_narrative():
    """Génère un récit hebdomadaire (~150 mots) style journaliste sportif."""
    from utils import _ai_rate_check
    if not _ai_rate_check():
        return jsonify({"error": "Trop de requêtes — réessaie dans quelques minutes."}), 429
    import os
    import anthropic as _anthropic
    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not api_key:
        return jsonify({"error": "ANTHROPIC_API_KEY manquant"}), 500
    try:
        data    = request.get_json(silent=True) or {}
        context = data.get("context", "")
        week    = data.get("week", "")
        if not context:
            return jsonify({"error": "Contexte manquant"}), 400

        client  = _anthropic.Anthropic(api_key=api_key)
        message = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=400,
            system=(
                "Tu es un journaliste sportif qui rédige le bilan hebdomadaire d'un athlète. "
                "À partir des données d'entraînement fournies, écris un récit de 100-150 mots. "
                "Style : direct, vivant, motivant. Mentionne les faits marquants : volume, RPE, récupération, progrès. "
                "Le progrès inclut l'augmentation des reps ET du poids — 8×15 lbs après 6×15 lbs est une victoire à souligner. "
                "Écris à la deuxième personne (tu/ton). Pas de bullet points, seulement du texte narratif. "
                "Termine sur une note d'anticipation pour la semaine suivante. Réponds uniquement en français."
            ),
            messages=[{"role": "user", "content": f"Données athlète:\n{context}"}]
        )
        narrative = message.content[0].text.strip()
        return jsonify({"narrative": narrative, "week": week})
    except Exception:
        raise


@ai_coach_bp.route("/api/ai/coach", methods=["POST"])
def api_ai_coach():
    from utils import _ai_rate_check, _now_mtl
    if not _ai_rate_check():
        return jsonify({"error": "Trop de requêtes — réessaie dans quelques minutes."}), 429
    import os
    import anthropic as _anthropic
    import db as _db
    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not api_key:
        return jsonify({"error": "ANTHROPIC_API_KEY manquant dans .env"}), 500
    try:
        data         = request.get_json(silent=True) or {}
        prompt       = data.get("prompt", "")       # legacy single-turn
        context      = data.get("context", "")      # rich athlete context (new)
        messages_in  = data.get("messages", [])     # full conversation history (new)

        # Build messages for Claude
        if messages_in:
            claude_messages = messages_in            # multi-turn: iOS owns the history
        elif prompt:
            claude_messages = [{"role": "user", "content": prompt}]
        else:
            return jsonify({"error": "Prompt vide"}), 400

        # Keep last 20 messages to avoid token overflow
        claude_messages = claude_messages[-20:]

        mode = data.get("mode", "custom")

        # System prompt — inject rich athlete context when provided
        system_base = (
            "Tu es un coach sportif expert en musculation, HIIT et périodisation de l'entraînement. "
            "Tu reçois des données réelles d'entraînement et tu les analyses avec rigueur. "
            "Règles importantes:\n"
            "- Ne compare JAMAIS le volume brut (lbs×reps) entre groupes musculaires — les jambes "
            "utilisent toujours des charges plus lourdes, ça ne veut pas dire qu'elles sont sur-entraînées.\n"
            "- Utilise le NOMBRE DE SETS par groupe musculaire comme indicateur de volume réel.\n"
            "- La surcharge progressive a DEUX dimensions : augmentation du POIDS et augmentation des REPS. "
            "  8 reps × 15 lbs > 6 reps × 15 lbs : c'est une progression réelle, même sans augmenter le poids. "
            "  Recommande d'augmenter les reps jusqu'au haut de la plage cible AVANT d'augmenter le poids.\n"
            "- Pour les suggestions de programme, sois précis: nomme les exercices à ajouter/retirer/modifier "
            "avec les schemes (ex: 3x8-10, 4x5-7).\n"
            "- Pour le HIIT, analyse la fréquence, les types et la récupération entre sessions.\n"
            "- Réponds toujours en français, de façon directe et actionnable."
        )
        system = f"{system_base}\n\nDONNÉES ATHLÈTE:\n{context}" if context else system_base

        logger.info("Claude coach — msgs=%d mode=%s", len(claude_messages), mode)
        client = _anthropic.Anthropic(api_key=api_key)
        message = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=1200,
            system=system,
            messages=claude_messages
        )
        response_text = message.content[0].text

        # Persist exchange in coach_history
        _db.insert_coach_message({
            "created_at": _now_mtl().strftime("%Y-%m-%dT%H:%M:00"),
            "mode":       mode,
            "assistant_response": response_text,
        })

        return jsonify({"response": response_text})
    except _anthropic.AuthenticationError:
        return jsonify({"error": "Clé ANTHROPIC_API_KEY invalide"}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@ai_coach_bp.route("/api/ai/post_workout", methods=["POST"])
def api_ai_post_workout():
    """Génère un bilan post-séance de 3 phrases comparant la séance actuelle à la précédente."""
    from utils import _ai_rate_check
    if not _ai_rate_check():
        return jsonify({"error": "Trop de requêtes — réessaie dans quelques minutes."}), 429
    import os
    import anthropic as _anthropic
    import db as _db
    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not api_key:
        return jsonify({"error": "ANTHROPIC_API_KEY manquant"}), 500
    try:
        data         = request.get_json(silent=True) or {}
        session_type = data.get("session_type", "")
        rpe          = data.get("rpe")
        exos         = data.get("exos", [])
        comment      = data.get("comment", "")
        date         = data.get("date", "")

        # Fetch last 5 sessions for context (previous same-type session)
        recent = _db.get_workout_sessions(limit=10)
        prev_same = next(
            (s for s in recent if s.get("session_name") == session_type and s.get("date") != date),
            None
        )

        ctx_lines = [f"Séance du jour ({date}) : {session_type}"]
        if rpe is not None:
            ctx_lines.append(f"RPE : {rpe}/10")
        if exos:
            ctx_lines.append(f"Exercices : {', '.join(exos)}")
        if comment:
            ctx_lines.append(f"Commentaire : {comment}")

        if prev_same:
            ctx_lines.append(f"\nSéance précédente de même type ({prev_same.get('date', '?')}) :")
            if prev_same.get("rpe") is not None:
                ctx_lines.append(f"RPE précédent : {prev_same['rpe']}/10")
            prev_exos = prev_same.get("exos") or []
            if prev_exos:
                ctx_lines.append(f"Exercices précédents : {', '.join(prev_exos)}")
        else:
            ctx_lines.append("\nAucune séance précédente du même type disponible.")

        context = "\n".join(ctx_lines)

        client = _anthropic.Anthropic(api_key=api_key)
        message = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=200,
            system=(
                "Tu es un coach sportif concis. À partir des données de séance fournies, "
                "rédige exactement 3 phrases en français : "
                "1) Évalue la performance de la séance d'aujourd'hui. "
                "2) Compare avec la séance précédente du même type (si disponible). "
                "3) Donne une recommandation concrète pour la prochaine séance. "
                "Style direct, motivant. Pas de bullet points. Uniquement les 3 phrases."
            ),
            messages=[{"role": "user", "content": context}]
        )
        brief = message.content[0].text.strip()
        return jsonify({"brief": brief})
    except Exception as e:
        logger.error("post_workout error: %s", e)
        return jsonify({"error": str(e)}), 500


@ai_coach_bp.route("/api/ai/coach/history")
def api_ai_coach_history():
    """Returns the last N coach exchanges."""
    import db as _db
    limit = min(int(request.args.get("limit", 20)), 50)
    history = _db.get_coach_history(limit=limit)
    return jsonify({"history": history})
