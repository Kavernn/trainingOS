from flask import Blueprint, jsonify, request
import logging

logger = logging.getLogger("trainingos")
ai_coach_program_bp = Blueprint("ai_coach_program", __name__)


def _build_program_context() -> str:
    """Build a compact athlete context string for programme generation."""
    import db as _db
    from weights import load_weights
    from inventory import load_inventory
    from sessions import load_sessions
    from utils import _calc_muscle_stats

    lines: [str] = []

    full_program = _db.get_full_program(None) or {}
    if full_program:
        from blocks import get_strength_exercises
        lines.append("PROGRAMME ACTUEL:")
        for seance, sdef in full_program.items():
            exos = get_strength_exercises(sdef) if isinstance(sdef, dict) and "blocks" in sdef else {}
            if exos:
                ex_str = ", ".join(f"{e}({s})" for e, s in exos.items())
                lines.append(f"  {seance}: {ex_str}")

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

    sessions_dict = load_sessions()
    muscle_stats = _calc_muscle_stats(sessions_dict, weights, inventory)
    if muscle_stats:
        lines.append("VOLUME PAR MUSCLE (volume_total, nb_séances):")
        for muscle, stats in sorted(muscle_stats.items(), key=lambda x: -x[1].get("sessions", 0)):
            lines.append(f"  {muscle}: {stats.get('sessions', 0)} séances, last={stats.get('last_date', '?')}")

    recent = _db.get_workout_sessions(limit=15)
    if recent:
        lines.append("SÉANCES RÉCENTES:")
        for s in recent:
            exos = s.get("exos") or []
            ex_str = "+".join(exos[:5]) if exos else "?"
            lines.append(f"  {s.get('date', '?')} {s.get('session_name', '?')} RPE={s.get('rpe', '?')} [{ex_str}]")

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


@ai_coach_program_bp.route("/api/ai/generate_program", methods=["POST"])
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
        logger.error("generate_program error: %s", e, exc_info=True)
        return jsonify({"error": "Erreur interne lors de la génération"}), 500


@ai_coach_program_bp.route("/api/ai/generated_program/latest", methods=["GET"])
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


@ai_coach_program_bp.route("/api/ai/generated_program/approve", methods=["POST"])
def api_ai_generated_program_approve():
    """Mark a generated program as active and link to its created programme."""
    import db as _db
    data         = request.get_json(silent=True) or {}
    gp_id        = data.get("id", "")
    programme_id = data.get("programme_id")
    if not gp_id:
        return jsonify({"error": "id manquant"}), 400
    ok = _db.update_generated_program(gp_id, "active", programme_id)
    return jsonify({"success": ok})
