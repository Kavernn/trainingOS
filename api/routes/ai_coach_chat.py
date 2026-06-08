from flask import Blueprint, jsonify, request
import logging

logger = logging.getLogger("trainingos")
ai_coach_bp = Blueprint("ai_coach", __name__)


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
        context     = (data.get("context", "") or "")[:4096]
        messages_in = data.get("messages", [])

        if messages_in:
            claude_messages = messages_in
        elif prompt:
            claude_messages = [{"role": "user", "content": prompt}]
        else:
            return jsonify({"error": "Prompt vide"}), 400

        claude_messages = claude_messages[-20:]

        last_user_message = next(
            (m.get("content", "") for m in reversed(claude_messages) if m.get("role") == "user"),
            ""
        )

        mode = data.get("mode", "custom")

        coach_name = "l'athlète"
        if context:
            m = re.search(r'\[([A-ZÀ-ÿ][a-zà-ÿ]+)', context)
            if m:
                coach_name = m.group(1)

        history_block = ""
        try:
            past = _db.get_coach_history(limit=5)
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
            "- Si une donnée est absente du contexte → réponds avec ce qui est disponible. N'invente jamais de chiffre.\n"
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

        # ── BLOC 3 — Format des réponses ─────────────────────────────────────
        bloc_format = (
            "FORMAT DES RÉPONSES — RÈGLES STRICTES :\n\n"
            "LONGUEUR :\n"
            "• Standard : 2-4 phrases. Analytique (pattern, corrélation) : 6 phrases max.\n"
            "• Jamais de listes à bullets dans une réponse conversationnelle.\n"
            "• Jamais de headers ou de gras dans une réponse.\n\n"
            "TON :\n"
            "• Direct. Concret. Sans politesse superflue.\n"
            "• Cite les chiffres réels du contexte — jamais de formules vagues.\n"
            "• Ne jamais répéter la question avant de répondre.\n"
            "• Une suggestion = une action précise avec un chiffre ('Essaie 190 lbs ce soir').\n\n"
            "FORMULES INTERDITES (zéro tolérance) :\n"
            "'En tant que ton coach' — 'Je n'ai pas accès à' — 'Mes données indiquent que'\n"
            "'Il est important de noter' — 'N'oublie pas que' — 'Je te recommande vivement'\n"
            "'Bien sûr !' — 'Absolument !' — 'C'est une excellente question'\n"
            "'Je serais ravi de t'aider' — toute phrase qui mentionne une limite de contexte.\n\n"
            "DONNÉES MANQUANTES :\n"
            "Si une donnée n'est pas dans le contexte → réponds avec ce qui est disponible, "
            "ou ignore ce point. Ne jamais signaler le manque à l'athlète."
        )

        # ── BLOC 4 — Guardrails absolus ───────────────────────────────────────
        bloc_guardrails = (
            "GUARDRAILS ABSOLUS — jamais dérogeables :\n\n"
            "G1 — ZÉRO HALLUCINATION\n"
            "N'invente jamais de tendance, de pourcentage, de chiffre absent du contexte. "
            "Si une donnée manque → utilise ce qui est disponible, ne mentionne pas le manque à l'athlète.\n\n"
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

        system_base = "\n\n".join([bloc_identity, bloc_fitness, bloc_format, bloc_guardrails])

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

        nutrition_block = ""
        try:
            from readiness import _score_nutrition
            nutr_score, nutr_details = _score_nutrition()
            if not nutr_details.get("no_data") and not nutr_details.get("error"):
                nlines = ["=== NUTRITION — QUALITÉ ==="]
                cal_pct  = nutr_details.get("cal_pct")
                prot_pct = nutr_details.get("prot_pct")
                score_line = f"Score qualité aujourd'hui : {int(nutr_score)}/100"
                if cal_pct is not None and prot_pct is not None:
                    score_line += f" (calories : {cal_pct}%, protéines : {prot_pct}%)"
                nlines.append(score_line)
                entries7 = _db.get_nutrition_entries_recent(7) or []
                logged_days = len({e.get("date") for e in entries7 if e.get("date")})
                nlines.append(f"Régularité 7j : {logged_days}/7 jours loggués")
                nutrition_block = "\n".join(nlines)
        except Exception:
            pass

        prog_block = ""
        try:
            from smart_progression import generate_suggestions
            recent = _db.get_workout_sessions(limit=1)
            if recent:
                s = recent[0]
                from utils import get_mesocycle_info
                meso  = get_mesocycle_info()
                phase = meso.get("phase")
                suggs = generate_suggestions(
                    session_date=s.get("date", ""),
                    session_type=s.get("session_type", "morning"),
                    session_name=s.get("session_name", ""),
                    phase=phase,
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

        last_session_block = ""
        try:
            recent_ls = _db.get_workout_sessions(limit=1)
            if recent_ls:
                ls      = recent_ls[0]
                ls_date = ls.get("date", "")
                ls_name = ls.get("session_name") or ""
                ls_dur  = ls.get("duration_min")
                ls_rpe  = ls.get("rpe")
                logs    = _db.get_session_exercise_logs(ls_date)
                if logs:
                    from collections import defaultdict
                    grouped: dict = defaultdict(list)
                    for log in logs:
                        name   = log.get("exercise_name", "")
                        weight = log.get("weight")
                        reps   = log.get("reps")
                        if name and weight is not None and reps is not None:
                            grouped[name].append(f"{weight}×{reps}")
                    if grouped:
                        header = f"{ls_name}, {ls_date}"
                        if ls_dur: header += f", {int(ls_dur)}min"
                        if ls_rpe: header += f", RPE {float(ls_rpe):.1f}"
                        ls_lines = [f"DERNIÈRE SÉANCE ({header}) :"]
                        for ex, sets in grouped.items():
                            ls_lines.append(f"  {ex} : {', '.join(sets)}")
                        last_session_block = "\n".join(ls_lines)
        except Exception:
            pass

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
        if last_session_block:
            system_parts.append(last_session_block)
        if acwr_block:
            system_parts.append(acwr_block)
        if nutrition_block:
            system_parts.append(nutrition_block)
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
            max_tokens=500,
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


@ai_coach_bp.route("/api/ai/coach/history")
def api_ai_coach_history():
    """Returns the last N coach exchanges."""
    import db as _db
    limit = min(int(request.args.get("limit", 20)), 50)
    history = _db.get_coach_history(limit=limit)
    return jsonify({"history": history})
