"""Routes — Daily Ritual ('Kill the old me / Let the new me rise')."""
from __future__ import annotations
from flask import Blueprint, jsonify, request
from datetime import date, timedelta, datetime, timezone
import random
import logging

logger = logging.getLogger("trainingos.ritual")
ritual_bp = Blueprint("ritual", __name__)

# ── Contextual suggestions per truth type ────────────────────────────────────

_SUGGESTIONS: dict[str, list[str]] = {
    "workout_gap": [
        "Je reprends aujourd'hui, peu importe la durée.",
        "Je fais au moins 20 minutes — peu importe comment je me sens.",
        "Je pose le téléphone avant de trouver une excuse.",
    ],
    "workout_skip": [
        "Je finis la séance même à 40% de mon niveau.",
        "Je ne négocie plus avec moi-même.",
        "J'arrête de reporter à demain ce que je peux tuer aujourd'hui.",
    ],
    "stress_rising": [
        "Je ne rajoute rien à ma liste aujourd'hui.",
        "Je m'arrête quand mon corps dit stop — pas après.",
        "Je dors avant minuit ce soir, sans négociation.",
    ],
    "stagnation": [
        "J'augmente un poids aujourd'hui, même de 2.5 kg.",
        "Je change une variable de ma routine — maintenant.",
        "Je dépasse mon dernier PR cette session.",
    ],
    "protein_gap": [
        "Je prépare mes repas ce soir, pas demain.",
        "Je cible 50g de protéines au premier repas.",
        "Je log chaque repas sans exception.",
    ],
    "sleep_debt": [
        "Je coupe les écrans 1h avant de dormir.",
        "Je vise 7h cette nuit — pas 6.",
        "Je note ce qui m'empêche de dormir et je l'élimine.",
    ],
    "default": [
        "Je montre qui je suis aujourd'hui.",
        "Je ne laisse pas la peur décider.",
        "Je deviens qui je veux être — maintenant, pas demain.",
    ],
}

_DEFAULT_TRUTHS = [
    ("Tu joues la sécurité depuis trop longtemps.", "default"),
    ("La version de toi d'il y a 6 mois ne ferait pas mieux.", "default"),
    ("Chaque jour sans intention est une journée perdue.", "default"),
    ("Tu sais exactement ce que tu dois changer. Tu ne le fais pas.", "default"),
    ("Il n'y a pas de version facile de ce que tu veux devenir.", "default"),
    ("L'ancienne version de toi survit parce que tu la laisses faire.", "default"),
]


# ── Truth generation ─────────────────────────────────────────────────────────

def _build_truth() -> tuple[str, str, list[str], dict]:
    """Return (truth_text, truth_type, suggestions[3], context_data) based on user data."""
    import db as _db

    today     = date.today()
    week_ago  = (today - timedelta(days=7)).isoformat()

    # 1. Days since last session ─────────────────────────────────────────────
    sessions = _db.get_workout_sessions(limit=14)
    if sessions:
        last_str = sessions[0].get("date", "")
        try:
            last_date  = date.fromisoformat(last_str)
            days_since = (today - last_date).days
            if days_since >= 4:
                t = f"Tu n'as pas touché une barre depuis {days_since} jours."
                ctx = {"jours_sans_séance": days_since, "dernière_séance": last_str}
                return t, "workout_gap", _SUGGESTIONS["workout_gap"], ctx
        except ValueError:
            pass

        # No session yet this week (Wed+) ───────────────────────────────────
        week_start = (today - timedelta(days=today.weekday())).isoformat()
        this_week  = [s for s in sessions if s.get("date", "") >= week_start]
        if not this_week and today.weekday() >= 2:
            day_names = {2: "mercredi", 3: "jeudi", 4: "vendredi", 5: "samedi", 6: "dimanche"}
            t = f"Zéro séance cette semaine — on est {day_names.get(today.weekday(), '')}."
            ctx = {"jour_semaine": day_names.get(today.weekday(), ""), "séances_cette_semaine": 0}
            return t, "workout_skip", _SUGGESTIONS["workout_skip"], ctx

        # RPE rising trend ───────────────────────────────────────────────────
        recent_rpes = [s["rpe"] for s in sessions[:7]  if s.get("rpe")]
        older_rpes  = [s["rpe"] for s in sessions[7:]  if s.get("rpe")]
        if len(recent_rpes) >= 3 and len(older_rpes) >= 3:
            avg_r = sum(recent_rpes) / len(recent_rpes)
            avg_o = sum(older_rpes)  / len(older_rpes)
            if avg_r > avg_o * 1.12:
                t = (f"Ton RPE monte depuis 2 semaines "
                     f"({avg_r:.1f} vs {avg_o:.1f}). La fatigue s'accumule sans que tu le voies.")
                ctx = {"RPE_récent_moyen": round(avg_r, 1), "RPE_précédent_moyen": round(avg_o, 1)}
                return t, "stress_rising", _SUGGESTIONS["stress_rising"], ctx

    # 2. Sleep debt ──────────────────────────────────────────────────────────
    recovery   = _db.get_recovery_logs(limit=7)
    sleep_vals = [r["sleep_hours"] for r in recovery if r.get("sleep_hours")]
    if len(sleep_vals) >= 3:
        avg_sleep = sum(sleep_vals) / len(sleep_vals)
        if avg_sleep < 6.5:
            t = (f"Tu dors {avg_sleep:.1f}h en moyenne cette semaine. "
                 f"Le manque de sommeil efface tes progrès.")
            ctx = {"sommeil_moyen_h": round(avg_sleep, 1), "jours_mesurés": len(sleep_vals)}
            return t, "sleep_debt", _SUGGESTIONS["sleep_debt"], ctx

    # 3. Protein gap ─────────────────────────────────────────────────────────
    nutrition_settings = _db.get_nutrition_settings()
    protein_goal = nutrition_settings.get("proteines") or nutrition_settings.get("protein_g")
    if protein_goal and protein_goal > 0:
        nutrition_days = _db.get_nutrition_entries_recent(7)
        if len(nutrition_days) >= 4:
            below = sum(
                1 for d in nutrition_days
                if d.get("proteines", 0) < protein_goal * 0.80
            )
            if below >= 4:
                t = (f"Tu n'as pas atteint tes protéines ({int(protein_goal)}g) "
                     f"depuis {below} des 7 derniers jours.")
                ctx = {
                    "objectif_protéines_g": int(protein_goal),
                    "jours_sous_objectif": below,
                    "jours_total_mesurés": len(nutrition_days),
                }
                return t, "protein_gap", _SUGGESTIONS["protein_gap"], ctx

    # 4. Default rotation ────────────────────────────────────────────────────
    text, ttype = random.choice(_DEFAULT_TRUTHS)
    return text, ttype, _SUGGESTIONS["default"], {}


# ── Claude-powered truth generation (wraps _build_truth) ─────────────────────

_TRUTH_SYSTEM = (
    "Tu génères LA vérité inconfortable du jour pour un athlète.\n\n"
    "RÈGLES STRICTES :\n"
    "- 1 à 2 phrases maximum. Pas plus.\n"
    "- Ton : factuel, direct. Pas cruel. Pas motivationnel.\n"
    "- Cite UN chiffre réel issu du contexte fourni. Pas de généralité.\n"
    "- Pas de point d'interrogation. Pas de 'peut-être'. Pas de 'tu devrais'.\n"
    "- Pas d'emoji. Pas d'exclamation.\n"
    "- La vérité constate — elle n'encourage pas.\n\n"
    "EXEMPLES DE TON :\n"
    "✓ 'Tu n'as pas touché une barre depuis 6 jours. Le corps oublie vite.'\n"
    "✓ 'Ton PSS a monté de 11 à 24 en 10 jours. La charge mentale précède toujours la régression physique.'\n"
    "✓ '4 jours sur 7 sous l'objectif protéines. Le muscle que tu construis en séance se reconstruit la nuit — avec de la protéine.'\n"
    "✗ 'Tu peux faire ça !' — interdit\n"
    "✗ 'C'est normal d'avoir des creux' — interdit\n"
    "✗ 'Rappelle-toi pourquoi tu as commencé' — interdit\n\n"
    "Réponds UNIQUEMENT avec les 1-2 phrases de vérité. Rien d'autre."
)


def _get_top_pattern_headline() -> str | None:
    """Pull today's daily pattern headline for injection into truth context. Best-effort."""
    try:
        import pattern_engine as _pe
        result = _pe.get_daily_pattern()
        daily  = result.get("daily")
        if daily and daily.get("headline"):
            return daily["headline"]
    except Exception:
        pass
    return None


def _generate_truth_with_claude(
    truth_type: str,
    fallback_truth: str,
    context_data: dict,
) -> str:
    """Call Claude to personalize the uncomfortable truth. Falls back to rule-based text on any error."""
    import os
    try:
        import anthropic
        api_key = os.environ.get("ANTHROPIC_API_KEY", "")
        if not api_key:
            return fallback_truth

        lines = [f"Type de vérité : {truth_type}"]
        for k, v in context_data.items():
            lines.append(f"{k} : {v}")

        # Inject pattern if available — gives Claude a real data point to reference
        pattern_headline = _get_top_pattern_headline()
        if pattern_headline:
            lines.append(f"pattern_du_jour : {pattern_headline}")

        user_content = "\n".join(lines)

        client = anthropic.Anthropic(api_key=api_key)
        msg = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=120,
            system=_TRUTH_SYSTEM,
            messages=[{"role": "user", "content": user_content}],
        )
        generated = (msg.content[0].text or "").strip()
        if generated and len(generated) > 10:
            return generated
    except Exception:
        pass
    return fallback_truth


# ── Phoenix streak computation ───────────────────────────────────────────────

def _compute_phoenix() -> tuple[int, int, int]:
    """Return (current_streak, best_streak, total_burned)."""
    import db as _db

    rows = _db.get_ritual_history(limit=365)
    if not rows:
        return 0, 0, 0

    total_burned = sum(1 for r in rows if r.get("outcome") == "burned")

    # Current streak — consecutive burned from most recent completed backward
    completed = [r for r in rows if r.get("outcome") in ("burned", "survived")]
    current = 0
    for r in completed:
        if r.get("outcome") == "burned":
            current += 1
        else:
            break

    # Best streak
    best, run = 0, 0
    for r in sorted(rows, key=lambda r: r.get("date", "")):
        if r.get("outcome") == "burned":
            run  += 1
            best  = max(best, run)
        elif r.get("outcome") == "survived":
            run = 0

    return current, best, total_burned


# ── Routes ───────────────────────────────────────────────────────────────────

@ritual_bp.route("/api/ritual/today")
def api_ritual_today():
    import db as _db

    today_str            = date.today().isoformat()
    existing             = _db.get_ritual_today(today_str)
    streak, best, total  = _compute_phoenix()
    demons               = _db.get_ritual_demons()

    if existing:
        ttype       = existing.get("truth_type", "default")
        suggestions = _SUGGESTIONS.get(ttype, _SUGGESTIONS["default"])
        return jsonify({
            **existing,
            "suggestions":           suggestions,
            "phoenix_streak":        streak,
            "phoenix_best":          best,
            "phoenix_total_burned":  total,
            "demons":                demons,
        })

    # No ritual today — generate truth + surface oldest demon
    truth, ttype, suggestions, ctx = _build_truth()
    truth = _generate_truth_with_claude(ttype, truth, ctx)

    carried_intention = None
    carried_from      = None
    carry_count       = 0
    survived_demons   = [d for d in demons if d.get("carry_count", 0) > 0]
    if survived_demons:
        oldest            = sorted(survived_demons, key=lambda d: d.get("date", ""))[0]
        carried_intention = oldest.get("intention")
        carried_from      = oldest.get("date")
        carry_count       = oldest.get("carry_count", 0)

    return jsonify({
        "date":                  today_str,
        "truth":                 truth,
        "truth_type":            ttype,
        "intention":             None,
        "morning_at":            None,
        "outcome":               None,
        "evening_at":            None,
        "carry_count":           carry_count,
        "carried_from":          carried_from,
        "carried_intention":     carried_intention,
        "suggestions":           suggestions,
        "phoenix_streak":        streak,
        "phoenix_best":          best,
        "phoenix_total_burned":  total,
        "demons":                demons,
    })


@ritual_bp.route("/api/ritual/morning", methods=["POST"])
def api_ritual_morning():
    import db as _db

    data      = request.get_json(silent=True) or {}
    intention = (data.get("intention") or "").strip()
    if not intention:
        return jsonify({"error": "intention is required"}), 400

    today_str = date.today().isoformat()
    now_iso   = datetime.now(timezone.utc).isoformat()
    existing  = _db.get_ritual_today(today_str) or {}

    if existing.get("truth"):
        truth, ttype = existing["truth"], existing["truth_type"]
    else:
        truth, ttype, _, ctx = _build_truth()
        truth = _generate_truth_with_claude(ttype, truth, ctx)

    payload = {
        "date":         today_str,
        "truth":        truth,
        "truth_type":   ttype,
        "intention":    intention,
        "morning_at":   existing.get("morning_at") or now_iso,
        "carry_count":  int(data.get("carry_count", 0)),
        "carried_from": data.get("carried_from"),
    }
    ok = _db.upsert_ritual(payload)
    if not ok:
        return jsonify({"error": "Erreur base de données"}), 500
    return jsonify({"ok": True})


@ritual_bp.route("/api/ritual/evening", methods=["POST"])
def api_ritual_evening():
    import db as _db

    data    = request.get_json(silent=True) or {}
    outcome = data.get("outcome", "")
    if outcome not in ("burned", "survived"):
        return jsonify({"error": "outcome must be 'burned' or 'survived'"}), 400

    today_str = date.today().isoformat()
    existing  = _db.get_ritual_today(today_str)
    if not existing or not existing.get("intention"):
        return jsonify({"error": "Complete the morning ritual first"}), 400

    now_iso = datetime.now(timezone.utc).isoformat()
    ok = _db.upsert_ritual({**existing, "outcome": outcome, "evening_at": now_iso})
    if not ok:
        return jsonify({"error": "Erreur base de données"}), 500

    streak, best, total = _compute_phoenix()
    return jsonify({
        "ok":                   True,
        "outcome":              outcome,
        "phoenix_streak":       streak,
        "phoenix_best":         best,
        "phoenix_total_burned": total,
    })


@ritual_bp.route("/api/ritual/streak")
def api_ritual_streak():
    streak, best, total = _compute_phoenix()
    return jsonify({
        "phoenix_streak":       streak,
        "phoenix_best":         best,
        "phoenix_total_burned": total,
    })
