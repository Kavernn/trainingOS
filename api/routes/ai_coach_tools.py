from flask import Blueprint, jsonify, request
import logging

logger = logging.getLogger("trainingos")
ai_coach_tools_bp = Blueprint("ai_coach_tools", __name__)


@ai_coach_tools_bp.route("/api/ai/propose", methods=["POST"])
def api_ai_propose():
    """Claude returns structured program modification proposals as JSON."""
    from utils import _ai_rate_check
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
    except _anthropic.BadRequestError as e:
        logger.error("ai/propose Anthropic 400: %s", e)
        return jsonify({"error": "Service IA indisponible — crédits insuffisants."}), 402
    except _anthropic.APIError as e:
        logger.error("ai/propose Anthropic API error: %s", e)
        return jsonify({"error": "Service IA temporairement indisponible."}), 503
    except Exception as e:
        logger.error("ai/propose unexpected error: %s", e)
        return jsonify({"error": "Erreur interne du serveur."}), 500


@ai_coach_tools_bp.route("/api/ai/narrative", methods=["POST"])
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
    except _anthropic.BadRequestError as e:
        logger.error("ai/narrative Anthropic 400: %s", e)
        return jsonify({"error": "Service IA indisponible — crédits insuffisants."}), 402
    except _anthropic.APIError as e:
        logger.error("ai/narrative Anthropic API error: %s", e)
        return jsonify({"error": "Service IA temporairement indisponible."}), 503
    except Exception as e:
        logger.error("ai/narrative unexpected error: %s", e)
        return jsonify({"error": "Erreur interne du serveur."}), 500


@ai_coach_tools_bp.route("/api/ai/post_workout", methods=["POST"])
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

        recent = _db.get_workout_sessions(limit=10)
        prev_same = next(
            (s for s in recent if s.get("session_name") == session_type and s.get("date") != date),
            None
        )

        ctx_lines = [f"Séance du jour ({date}) : {session_type}"]
        if rpe is not None:
            ctx_lines.append(f"RPE : {rpe}/10")

        detailed_exos = []
        try:
            import json as _json_inner
            s_row = _db.get_workout_session_by_type(date, "morning") or _db.get_workout_session_by_type(date, "evening")
            if s_row:
                logs = _db.get_exercise_logs_for_session_with_names(s_row["id"])
                for log in logs:
                    name = log.get("exercise_name", "")
                    sets_data = log.get("sets_json") or []
                    if isinstance(sets_data, str):
                        try:
                            sets_data = _json_inner.loads(sets_data)
                        except Exception:
                            sets_data = []
                    if sets_data:
                        sets_str = " / ".join(
                            f"{s.get('weight','?')}lbs×{s.get('reps','?')}" for s in sets_data
                        )
                        detailed_exos.append(f"{name}: {sets_str}")
                    elif log.get("weight") is not None:
                        detailed_exos.append(f"{name}: {log['weight']}lbs×{log.get('reps','?')}")
                    else:
                        detailed_exos.append(name)
        except Exception:
            pass

        if detailed_exos:
            ctx_lines.append("Exercices (poids×reps par série) :")
            ctx_lines.extend(f"  {e}" for e in detailed_exos)
        elif exos:
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
            max_tokens=350,
            system=(
                "Tu es un coach sportif concis. À partir des données de séance fournies, "
                "rédige exactement 3 phrases complètes en français : "
                "1) Évalue la performance de la séance d'aujourd'hui avec un chiffre concret (RPE, volume ou exercice). "
                "2) Compare avec la séance précédente du même type — cite la différence précise (si données disponibles). "
                "3) Donne une recommandation actionnable pour la prochaine séance (poids, schème, ou récupération). "
                "Style direct, motivant. Pas de bullet points. Uniquement les 3 phrases."
            ),
            messages=[{"role": "user", "content": context}]
        )
        brief = message.content[0].text.strip()
        return jsonify({"brief": brief})
    except _anthropic.BadRequestError as e:
        logger.error("ai/post_workout Anthropic 400: %s", e)
        return jsonify({"error": "Service IA indisponible — crédits insuffisants."}), 402
    except _anthropic.APIError as e:
        logger.error("ai/post_workout Anthropic API error: %s", e)
        return jsonify({"error": "Service IA temporairement indisponible."}), 503
    except Exception as e:
        logger.error("ai/post_workout unexpected error: %s", e)
        return jsonify({"error": "Erreur interne du serveur."}), 500
