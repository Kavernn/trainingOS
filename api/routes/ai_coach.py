from flask import Blueprint, jsonify, request
import logging

logger = logging.getLogger("trainingos")

ai_coach_bp = Blueprint("ai_coach", __name__)


@ai_coach_bp.route("/api/ai/propose", methods=["POST"])
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
    import os, re
    import anthropic as _anthropic
    import db as _db
    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not api_key:
        return jsonify({"error": "ANTHROPIC_API_KEY manquant dans .env"}), 500
    try:
        data        = request.get_json(silent=True) or {}
        prompt      = data.get("prompt", "")
        context     = data.get("context", "")
        messages_in = data.get("messages", [])

        if messages_in:
            claude_messages = messages_in
        elif prompt:
            claude_messages = [{"role": "user", "content": prompt}]
        else:
            return jsonify({"error": "Prompt vide"}), 400

        claude_messages = claude_messages[-20:]

        # Extract last user message for persistence
        last_user_message = next(
            (m.get("content", "") for m in reversed(claude_messages) if m.get("role") == "user"),
            ""
        )

        mode = data.get("mode", "custom")

        # Extract first name from context line "[Prénom Nom ...]"
        coach_name = "l'athlète"
        if context:
            m = re.search(r'\[([A-ZÀ-ÿ][a-zà-ÿ]+)', context)
            if m:
                coach_name = m.group(1)

        # Cross-session history from Supabase — injected as context, not as Claude messages
        history_block = ""
        try:
            past = _db.get_coach_history(limit=10)
            past = [p for p in reversed(past) if p.get("user_message") or p.get("assistant_response")]
            if past:
                lines = ["=== HISTORIQUE DES SESSIONS PRÉCÉDENTES ==="]
                for p in past:
                    ts = (p.get("created_at") or "")[:10]
                    if p.get("user_message"):
                        lines.append(f"[{ts}] {coach_name}: {p['user_message']}")
                    if p.get("assistant_response"):
                        lines.append(f"[{ts}] Coach: {p['assistant_response']}")
                lines.append("===")
                history_block = "\n".join(lines)
        except Exception:
            pass

        # ── BLOC 1 — Identité & philosophie ──────────────────────────────────
        bloc_identity = (
            f"Tu es le coach personnel de {coach_name}. Tu as accès à ses données en temps réel.\n\n"
            "TON RÔLE :\n"
            "Un coach qui respecte l'athlète assez pour ne pas lui mentir. "
            "Factuel, direct, zéro bullshit. Pas un thérapeute. Pas un cheerleader.\n\n"
            "PROTOCOLE :\n"
            "- Chaque observation cite une donnée précise : exercice nommé, date, chiffre exact.\n"
            "- Chaque recommandation a une raison data-driven, pas une règle générique.\n"
            "- Si une donnée est absente, dis-le. N'invente jamais.\n"
            "- Les corrélations cross-piliers sont ta valeur ajoutée — utilise-les activement "
            "et ne les cite QUE si elles figurent dans le bloc CORRÉLATIONS de ce contexte.\n"
            "- Tu te souviens des conversations précédentes et tu fais des suivis explicites.\n\n"
            "Structure implicite de chaque réponse (sans labels) :\n"
            "→ Observation ancrée dans les données réelles (date, chiffre, exercice nommé)\n"
            "→ Corrélation avec un autre pilier si présente dans les données (Body / Mind / Fuel / Spirit)\n"
            "→ Action concrète avec une échéance précise\n\n"
            "ÉCHELLE DE TONALITÉ :\n"
            "• Quand ça va bien  → reconnaissance sobre. "
            "'You're building on solid ground. Keep stacking days.' "
            "Jamais 'WOW INCROYABLE 🔥💪'.\n"
            "• Quand ça stagne   → vérité factuelle. "
            "'Volume flat depuis 3 semaines. On ajuste le stimulus.'\n"
            "• Quand ça régresse → vérité nue, sans cruauté. "
            "'Volume en baisse, PSS en hausse. Ajuste avant que le plateau s'installe.'\n"
            "• War Room actif    → pair-à-pair, factuel. "
            "'Today is about holding the line, not pushing it.' Jamais condescendant.\n"
            "Réponds toujours en français sauf les phrases d'exemple ci-dessus."
        )

        # ── BLOC 2 — Règles fitness (immuables) ──────────────────────────────
        bloc_fitness = (
            "RÈGLES TECHNIQUES — NON NÉGOCIABLES :\n\n"
            "CLASSIFICATION DES EXERCICES :\n"
            "• Compound lourd    → 5-7 reps  (squat, deadlift, bench, OHP, row lourd)\n"
            "• Compound hypertro → 8-12 reps (variantes, tempo, RDL, incline, cable row)\n"
            "• Isolation         → 12-15 reps (curl, extension, fly, lat raise)\n\n"
            "ÉVALUATION DU WAVE LOADING :\n"
            "• Évalue UNIQUEMENT sur le dernier working set (set le plus lourd).\n"
            "• Un set de 6×100kg après 4×90kg → le 6×100kg est le set à évaluer.\n"
            "• Ignore les sets de chauffe dans l'analyse de performance.\n\n"
            "PROGRESSION :\n"
            "• Upper body : +2.5 à +5 lbs max par palier.\n"
            "• Lower body : +5 à +10 lbs max par palier.\n"
            "• Critère d'avancement : dernier working set complété proprement sur 2 séances consécutives.\n"
            "• Si RPE > 9 sur dernier set → maintenir le poids, ajouter 1 rep d'abord.\n\n"
            "VOLUME :\n"
            "• Utilise le NOMBRE DE SETS par groupe comme indicateur de volume réel.\n"
            "• Ne compare JAMAIS le volume brut (lbs×reps) entre groupes musculaires différents.\n"
            "• La surcharge progressive a deux dimensions : poids ET reps. "
            "8×15 lbs > 6×15 lbs est un vrai progrès.\n\n"
            "DÉCHARGE :\n"
            "• RPE moyen > 8.5 sur 3 séances consécutives → signale la surcharge. "
            "Suggère décharge ou modification.\n"
            "• ACWR > 1.5 → recommande réduction de charge ou récupération active."
        )

        # ── BLOC 4 — Guardrails absolus ───────────────────────────────────────
        bloc_guardrails = (
            "GUARDRAILS ABSOLUS — jamais dérogeables :\n\n"
            "G1 — ZÉRO HALLUCINATION\n"
            "Si tu n'as pas la donnée : 'Je n'ai pas ces données pour cette période.' "
            "N'invente jamais de tendance, de pourcentage, de chiffre.\n\n"
            "G2 — JOURNAL SACRÉ\n"
            "Le contenu du journal spirituel (gratitude, conquered, haunting) ne t'est jamais transmis. "
            "Si l'athlète colle du texte ressemblant à une entrée de journal, réponds uniquement : "
            "'Ce que tu écris dans le journal t'appartient. Je ne travaille pas avec ce contenu.' "
            "Tu n'as accès qu'aux counts : '3 entrées cette semaine.' Jamais au contenu.\n\n"
            "G3 — WAR ROOM SANDBOXÉ\n"
            "Si war_room_shared = false → le bloc War Room n'existe pas pour toi. "
            "Si shared = true → uniquement streak/rate/days_since_reset. "
            "Triggers, notes de battle, arsenal → jamais exposés, jamais référencés.\n\n"
            "G4 — LANGAGE THÉRAPEUTE INTERDIT STRICT\n"
            "Mots bannis : 'je suis fier de toi', 'tu n'es pas seul', 'chaque petit pas compte', "
            "'tu mérites', 'prends soin de toi', 'c'est normal de', 'je comprends que tu traverses', "
            "'rappelle-toi que', 'tu as fait de ton mieux', 'c'est courageux'.\n\n"
            "G5 — ZÉRO MORALISATION\n"
            "Ne juge jamais une rechute, un écart alimentaire, une séance ratée. "
            "Constater les données, proposer un ajustement. C'est tout.\n\n"
            "G6 — ZÉRO CONDESCENDANCE SUR L'ADDICTION\n"
            "Pas de 'tu peux le faire', pas de 'chaque jour est une victoire', "
            "pas de trophées pour tenir. L'athlète sait ce qu'il fait. Faits et plan. C'est tout.\n\n"
            "G7 — CORRÉLATION FICTIVE INTERDITE\n"
            "Ne cite une corrélation cross-pilier QUE si elle figure dans le bloc "
            "CORRÉLATIONS DÉTECTÉES de ce contexte. N'invente aucun lien."
        )

        system_base = "\n\n".join([bloc_identity, bloc_fitness, bloc_guardrails])

        # Correlations block — top 3 significant pairs with effect size
        corr_block = ""
        try:
            from correlations import get_correlations
            corr_data = get_correlations(days=60)
            top_corrs = corr_data.get("insights", [])[:3]
            if top_corrs:
                lines = [
                    "CORRÉLATIONS CROSS-PILIERS DÉTECTÉES (données réelles, n >= 5) :",
                    "→ Tu peux citer ces corrélations dans tes réponses — ce sont des faits mesurés.",
                    "→ N'invente aucun lien qui ne figure pas ici.",
                ]
                for c in top_corrs:
                    pct = c.get("effect_pct")
                    pct_str = f" [{pct:+.0f}% d'écart entre groupes]" if pct is not None else ""
                    lines.append(f"  • {c['description']}{pct_str}")
                corr_block = "\n".join(lines)
        except Exception:
            pass

        # ACWR block — charge aiguë/chronique (Gabbett 2016, EWMA)
        acwr_block = ""
        try:
            from acwr import calc_acwr
            acwr_data = calc_acwr()
            acwr_ratio = float(acwr_data.get("ratio") or 0)
            acwr_zone  = (acwr_data.get("zone") or {})
            acwr_conf  = acwr_data.get("confidence", "low")
            acwr_days  = acwr_data.get("days_of_data", 0)
            if acwr_days >= 7 and acwr_conf in ("moderate", "high"):
                zone_label = acwr_zone.get("label", "")
                zone_reco  = acwr_zone.get("recommendation", "")
                acwr_block = (
                    f"=== CHARGE AIGUË/CHRONIQUE (ACWR EWMA) ===\n"
                    f"Ratio : {acwr_ratio:.2f} — {zone_label}\n"
                    f"Recommandation : {zone_reco}\n"
                    f"Données : {acwr_days} jours (confiance : {acwr_conf})"
                )
        except Exception:
            pass

        # Progression suggestions block — from smart_progression engine
        prog_block = ""
        try:
            from smart_progression import generate_suggestions
            recent = _db.get_workout_sessions(limit=1)
            if recent:
                s = recent[0]
                suggs = generate_suggestions(
                    session_date=s.get("date", ""),
                    session_type=s.get("session_type", "morning"),
                    session_name=s.get("session_name", ""),
                )
                actionable = [sg for sg in suggs if sg.get("suggestion_type") != "maintain"][:5]
                if actionable:
                    lines = ["SUGGESTIONS DE PROGRESSION (moteur analytique — cite-les dans ta réponse):"]
                    for sg in actionable:
                        name = sg.get("exercise_name", "")
                        st   = sg.get("suggestion_type", "")
                        reason = sg.get("reason", "")
                        sw   = sg.get("suggested_weight")
                        sw_str = f" → {sw} lbs" if sw else ""
                        lines.append(f"  • {name}{sw_str} [{st}]: {reason}")
                    prog_block = "\n".join(lines)
        except Exception:
            pass

        # Spirit context block (metadata only — zero content)
        spirit_block = ""
        try:
            spirit = _db.get_spirit_metadata(days=7)
            bw = spirit.get("breathwork_count", 0)
            med = spirit.get("meditation_count", 0)
            jrn = spirit.get("journal_count", 0)
            if bw or med or jrn:
                bw_streak = spirit.get("breathwork_streak", 0)
                lines = ["=== PILIER SPIRIT (7 derniers jours) ==="]
                bw_s = "s" if bw != 1 else ""
                lines.append(f"Breathwork : {bw} session{bw_s}")
                if bw_streak >= 2:
                    lines.append(f"  Streak breathwork : {bw_streak} jours consécutifs")
                med_s = "s" if med != 1 else ""
                lines.append(f"Méditation : {med} session{med_s} complétée{med_s}")
                jrn_s = "s" if jrn != 1 else ""
                lines.append(f"Journal sacré : {jrn} entrée{jrn_s} (contenu non transmis — accès interdit)")
                spirit_block = "\n".join(lines)
        except Exception:
            pass

        # War Room context block (conditional on explicit opt-in)
        war_room_block = ""
        war_room_mode_block = ""
        try:
            if _db.get_coach_war_room_shared():
                wr = _db.get_war_room_coach_context()
                if wr:
                    streak = wr.get("streak", 0)
                    best = wr.get("best_streak", 0)
                    victories = wr.get("victories", 0)
                    total = wr.get("total_battles", 0)
                    dsr = wr.get("days_since_reset")
                    last_reset = wr.get("last_reset_date")

                    if dsr is not None and dsr < 7:
                        wr_mode = "POST_RESET"
                    elif streak >= 14:
                        wr_mode = "MOMENTUM"
                    else:
                        wr_mode = "STABLE"

                    lines = ["=== WAR ROOM (partagé avec le coach) ==="]
                    lines.append(f"Streak actuel : {streak} jour{'s' if streak != 1 else ''}")
                    lines.append(f"Record personnel : {best} jours")
                    rate = f"{round(victories / total * 100)}%" if total > 0 else "—"
                    lines.append(f"Victoires / combats (90j) : {victories}/{total} ({rate})")
                    if last_reset:
                        dsr_str = f" — il y a {dsr}j" if dsr is not None else ""
                        lines.append(f"Dernier reset : {last_reset}{dsr_str}")
                    else:
                        lines.append("Aucun reset enregistré")
                    lines.append(f"Mode : {wr_mode}")
                    war_room_block = "\n".join(lines)

                    if wr_mode == "POST_RESET":
                        war_room_mode_block = (
                            "[WAR_ROOM_POST_RESET — BLOC 3 TON]\n"
                            f"Jours depuis reset : {dsr}. Mode : stabilisation.\n"
                            "PRIORITÉS (ordre strict) : "
                            "1. breathwork ou méditation  2. workout léger RPE ≤ 6  3. rien d'autre.\n"
                            "TON : un soldat qui parle à un autre soldat. Factuel. Aucun commentaire sur le reset.\n"
                            "FORMULATIONS AUTORISÉES :\n"
                            "  'Today is about holding the line, not pushing it.'\n"
                            "  'Stabilise d'abord. La performance suit.'\n"
                            "  'Une journée de plus. C'est l'objectif.'\n"
                            "INTERDITS ABSOLUS : référence au courage ou à la chute, "
                            "comparaisons avec semaines précédentes, push d'intensité maximale, "
                            "tout langage d'encouragement émotionnel."
                        )
                    elif wr_mode == "MOMENTUM":
                        war_room_mode_block = (
                            "[WAR_ROOM_MOMENTUM — BLOC 3 TON]\n"
                            f"Streak actuel : {streak} jours. Momentum solide.\n"
                            "AUTORISÉ : UNE seule reconnaissance factuelle par conversation max.\n"
                            "Doit citer le streak ET une stat physique réelle.\n"
                            "FORMULATIONS AUTORISÉES :\n"
                            f"  '{streak}j de victoires + [stat physique]. Tu construis sur du solide.'\n"
                            "  'You're building on solid ground. Keep stacking days.'\n"
                            "INTERDITS : superlatifs, comparaisons avec d'autres, "
                            "langage motivationnel générique, plus d'une reconnaissance par échange."
                        )
        except Exception:
            pass

        system_parts = [system_base]
        if context:
            system_parts.append(f"DONNÉES ATHLÈTE EN TEMPS RÉEL:\n{context}")
        if acwr_block:
            system_parts.append(acwr_block)
        if spirit_block:
            system_parts.append(spirit_block)
        if war_room_block:
            system_parts.append(war_room_block)
        if war_room_mode_block:
            system_parts.append(war_room_mode_block)
        if corr_block:
            system_parts.append(corr_block)
        if prog_block:
            system_parts.append(prog_block)
        if history_block:
            system_parts.append(history_block)
        system = "\n\n".join(system_parts)

        logger.info("Claude coach — msgs=%d mode=%s history_chars=%d", len(claude_messages), mode, len(history_block))
        client = _anthropic.Anthropic(api_key=api_key)
        message = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=2000,
            system=system,
            messages=claude_messages
        )
        response_text = message.content[0].text

        _db.insert_coach_message({
            "created_at":         _now_mtl().strftime("%Y-%m-%dT%H:%M:00"),
            "mode":               mode,
            "user_message":       last_user_message,
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

        # Try to fetch detailed exercise logs (weights + reps) from DB
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


# ---------------------------------------------------------------------------
# Programme generator endpoints
# ---------------------------------------------------------------------------

def _build_program_context() -> str:
    """Build a compact athlete context string for programme generation."""
    import db as _db
    from weights import load_weights
    from inventory import load_inventory
    from sessions import load_sessions
    from utils import _calc_muscle_stats

    lines: [str] = []

    # Current programme structure
    full_program = _db.get_full_program(None) or {}
    if full_program:
        from blocks import get_strength_exercises
        lines.append("PROGRAMME ACTUEL:")
        for seance, sdef in full_program.items():
            exos = get_strength_exercises(sdef) if isinstance(sdef, dict) and "blocks" in sdef else {}
            if exos:
                ex_str = ", ".join(f"{e}({s})" for e, s in exos.items())
                lines.append(f"  {seance}: {ex_str}")

    # Exercise progression (top 15 by recent weight)
    weights = load_weights()
    inventory = load_inventory() or {}
    top_exos = sorted(weights.items(), key=lambda x: x[1].get("current_weight") or 0, reverse=True)[:15]
    if top_exos:
        lines.append("PROGRESSION EXERCICES (nom: poids×reps):")
        for name, w in top_exos:
            hist = w.get("history", [])[:3]
            hist_str = " ".join(f"{h.get('weight', 0)}×{h.get('reps', '')}" for h in hist)
            muscles = (inventory.get(name) or {}).get("muscles") or []
            m_str = f" [{','.join(muscles)}]" if muscles else ""
            lines.append(f"  {name}{m_str}: {hist_str}")

    # Muscle stats (volume + sessions per group)
    sessions_dict = load_sessions()
    muscle_stats = _calc_muscle_stats(sessions_dict, weights, inventory)
    if muscle_stats:
        lines.append("VOLUME PAR MUSCLE (volume_total, nb_séances):")
        for muscle, stats in sorted(muscle_stats.items(), key=lambda x: -x[1].get("sessions", 0)):
            lines.append(f"  {muscle}: {stats.get('sessions', 0)} séances, last={stats.get('last_date', '?')}")

    # Recent sessions (last 15)
    recent = _db.get_workout_sessions(limit=15)
    if recent:
        lines.append("SÉANCES RÉCENTES:")
        for s in recent:
            exos = s.get("exos") or []
            ex_str = "+".join(exos[:5]) if exos else "?"
            lines.append(f"  {s.get('date', '?')} {s.get('session_name', '?')} RPE={s.get('rpe', '?')} [{ex_str}]")

    # Recovery (last 7)
    recovery = _db.get_recovery_logs(limit=7)
    if recovery:
        lines.append("RÉCUPÉRATION RÉCENTE (date: sommeil, hrv, soreness):")
        for r in recovery:
            lines.append(
                f"  {r.get('date', '?')}: "
                f"sommeil={r.get('sleep_hours', '?')}h "
                f"hrv={r.get('hrv', '?')} "
                f"soreness={r.get('soreness', '?')}"
            )

    return "\n".join(lines)


@ai_coach_bp.route("/api/ai/generate_program", methods=["POST"])
def api_ai_generate_program():
    """Generate a 4-week hypertrophy programme using Claude, store in generated_programs."""
    from utils import _ai_rate_check
    if not _ai_rate_check():
        return jsonify({"error": "Trop de requêtes — réessaie dans quelques minutes."}), 429
    import os, json as _json
    import anthropic as _anthropic
    import db as _db

    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not api_key:
        return jsonify({"error": "ANTHROPIC_API_KEY manquant"}), 500

    try:
        context = _build_program_context()
        logger.info("generate_program — context_len=%d", len(context))

        client = _anthropic.Anthropic(api_key=api_key)
        message = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=6000,
            system=(
                "Tu es un coach expert en programmation musculaire scientifique. "
                "Tu génères un programme d'hypertrophie de 4 semaines / 5 jours par semaine, "
                "basé sur les données réelles de l'athlète.\n\n"
                "PRINCIPES OBLIGATOIRES:\n"
                "- Volume: 10–20 sets par groupe musculaire par semaine\n"
                "- Fréquence: chaque groupe musculaire 2× minimum par semaine\n"
                "- Jamais le même groupe musculaire 2 jours consécutifs\n"
                "- Progressive overload: le volume/intensité augmente chaque semaine\n"
                "- Semaine 4 = deload: 50-60% du volume des semaines précédentes\n"
                "- Utilise les exercices du programme actuel comme base\n"
                "- Propose de nouveaux exercices si un groupe manque de variété\n\n"
                "RANGES DE REPS PAR CATÉGORIE (obligatoire):\n"
                "- compound_heavy (squat, deadlift, bench, row lourd) : reps='4-6' ou '6-8', rest_sec=180-240\n"
                "- compound_hypertrophy (presses, tractions, rowing modéré) : reps='8-12', rest_sec=90-120\n"
                "- isolation (curls, extensions, élévations latérales) : reps='12-15', rest_sec=60-90\n\n"
                "STRUCTURE DES PHASES:\n"
                "- Semaine 1: accumulation (volume modéré, apprentissage)\n"
                "- Semaine 2: intensification (volume +1 set/exo)\n"
                "- Semaine 3: peak (volume maximum, intensité haute)\n"
                "- Semaine 4: deload (volume 50-60%, récupération active)\n\n"
                "RÉPONDS UNIQUEMENT avec un objet JSON valide, sans texte avant ni après.\n"
                "Format exact:\n"
                '{\n'
                '  "name": "Hypertrophie 4 semaines",\n'
                '  "weeks": [\n'
                '    {\n'
                '      "week": 1,\n'
                '      "phase": "accumulation",\n'
                '      "days": [\n'
                '        {\n'
                '          "day": 1,\n'
                '          "name": "Push A",\n'
                '          "muscle_focus": ["chest", "shoulders", "triceps"],\n'
                '          "exercises": [\n'
                '            {\n'
                '              "name": "Bench Press",\n'
                '              "category": "compound_heavy",\n'
                '              "muscle_group": "chest",\n'
                '              "sets": 4,\n'
                '              "reps": "6-8",\n'
                '              "rest_sec": 180,\n'
                '              "rationale": "explication courte"\n'
                '            }\n'
                '          ]\n'
                '        }\n'
                '      ]\n'
                '    }\n'
                '  ],\n'
                '  "schedule": {"Lun": "Push A", "Mar": "Pull A", "Mer": "Legs", "Jeu": "Push B", "Ven": "Pull B"},\n'
                '  "muscle_volume": {\n'
                '    "chest": {"sets_per_week": 12, "frequency": 2}\n'
                '  },\n'
                '  "global_rationale": "Explication globale du programme"\n'
                '}'
            ),
            messages=[{"role": "user", "content": f"Données athlète:\n{context}"}]
        )

        raw = message.content[0].text.strip()
        # Extract JSON object from response
        start = raw.find('{')
        end   = raw.rfind('}') + 1
        if start == -1 or end == 0:
            logger.error("generate_program: no JSON object in response — raw=%s", raw[:300])
            return jsonify({"error": "Réponse non structurée du modèle"}), 500

        try:
            program_json = _json.loads(raw[start:end])
        except _json.JSONDecodeError as e:
            logger.error("generate_program JSON decode error: %s — raw=%s", e, raw[:300])
            return jsonify({"error": "JSON invalide retourné par le modèle"}), 500

        # Validate minimal structure
        if "weeks" not in program_json or not isinstance(program_json["weeks"], list):
            return jsonify({"error": "Structure de programme invalide"}), 500

        gp_id = _db.save_generated_program(program_json)
        if not gp_id:
            return jsonify({"error": "Erreur de sauvegarde"}), 500

        return jsonify({
            "id":           gp_id,
            "generated_at": "",
            "status":       "pending_approval",
            "program_json": program_json,
        })

    except _anthropic.AuthenticationError:
        return jsonify({"error": "Clé ANTHROPIC_API_KEY invalide"}), 500
    except Exception as e:
        logger.error("generate_program error: %s", e)
        raise


@ai_coach_bp.route("/api/ai/generated_program/latest", methods=["GET"])
def api_ai_generated_program_latest():
    """Return the most recent generated program (any status)."""
    import db as _db
    row = _db.get_latest_generated_program()
    if not row:
        return jsonify(None), 200
    return jsonify({
        "id":           row["id"],
        "generated_at": str(row.get("generated_at", "")),
        "status":       row.get("status", "pending_approval"),
        "program_json": row["program_json"],
    })


@ai_coach_bp.route("/api/ai/generated_program/approve", methods=["POST"])
def api_ai_generated_program_approve():
    """Mark a generated program as active and link to its created programme."""
    import db as _db
    data         = request.get_json(silent=True) or {}
    gp_id        = data.get("id", "")
    programme_id = data.get("programme_id")  # optional
    if not gp_id:
        return jsonify({"error": "id manquant"}), 400
    ok = _db.update_generated_program(gp_id, "active", programme_id)
    return jsonify({"success": ok})


# ---------------------------------------------------------------------------
# Coach Memory — server-side persistence
# ---------------------------------------------------------------------------

@ai_coach_bp.route("/api/coach/memory", methods=["GET"])
def get_coach_memory():
    """Return the coach memory entries stored in user_profile."""
    import db as _db
    entries = _db.get_coach_memory()
    return jsonify({"entries": entries})


@ai_coach_bp.route("/api/coach/memory", methods=["POST"])
def save_coach_memory():
    """Persist coach memory entries. Replaces the full set."""
    import db as _db
    data    = request.get_json(silent=True) or {}
    entries = data.get("entries")
    if not isinstance(entries, list):
        return jsonify({"error": "entries must be a list"}), 400
    ok = _db.save_coach_memory(entries)
    return jsonify({"success": ok})


# ---------------------------------------------------------------------------
# War Room share toggle — explicit opt-in to expose War Room stats to coach
# ---------------------------------------------------------------------------

@ai_coach_bp.route("/api/coach/war_room_share", methods=["GET"])
def get_war_room_share():
    """Return whether the user has opted in to sharing War Room data with the coach."""
    import db as _db
    return jsonify({"shared": _db.get_coach_war_room_shared()})


@ai_coach_bp.route("/api/coach/war_room_share", methods=["POST"])
def set_war_room_share():
    """Toggle War Room sharing with the coach. Body: {"shared": bool}"""
    import db as _db
    data  = request.get_json(silent=True) or {}
    value = bool(data.get("shared", False))
    ok    = _db.set_coach_war_room_shared(value)
    return jsonify({"success": ok, "shared": value})

