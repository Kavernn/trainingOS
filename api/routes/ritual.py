"""Routes — Daily Ritual ('Kill the old me / Let the new me rise')."""
from __future__ import annotations
from flask import Blueprint, jsonify, request
from datetime import date, timedelta, datetime, timezone
import random
import logging
from utils import _today_mtl_date as _today_mtl

logger = logging.getLogger("trainingos.ritual")
ritual_bp = Blueprint("ritual", __name__)


# ── Suggestions par type de vérité ───────────────────────────────────────────

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
    "pss_high": [
        "Je médite 10 minutes avant de déclarer ma guerre.",
        "Je coupe une source de stress identifiable aujourd'hui.",
        "Je priorise la récupération mentale autant que physique.",
    ],
    "session_heavy": [
        "Je me prépare mentalement — cette séance est un combat.",
        "Je ne renegocie pas à la barre. Je suis venu pour ça.",
        "Je donne 100% sur les sets clés — c'est tout.",
    ],
    "recovery_day": [
        "Je récupère activement — mobilité, sommeil, nutrition.",
        "Je prends le repos aussi sérieusement qu'une séance.",
        "Je nourris le corps pour qu'il reconstruise.",
    ],
    "streak_reset": [
        "Je recommence. Le streak est cassé, pas moi.",
        "Une nuit à côté ne définit pas la trajectoire.",
        "Je rebuild à partir d'aujourd'hui.",
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


# ── Carry count computation from actual dates (A1) ──────────────────────────

def _enrich_carry_counts(demons: list[dict]) -> list[dict]:
    """Recompute carry_count from actual date difference — never trust stored value."""
    today = _today_mtl()
    enriched = []
    for d in demons:
        try:
            demon_date = date.fromisoformat(d["date"])
            actual_carry = (today - demon_date).days
            enriched.append({**d, "carry_count": actual_carry})
        except Exception:
            enriched.append(d)
    return enriched


# ── Truth generation ─────────────────────────────────────────────────────────

def _build_truth(phoenix_streak: int = 0) -> tuple[str, str, list[str], dict]:
    """Return (truth_text, truth_type, suggestions[3], context_data) based on user data."""
    import db as _db

    today = _today_mtl()

    # C3: Streak just reset — yesterday survived and today streak is 0
    yesterday_str = (today - timedelta(days=1)).isoformat()
    yesterday_ritual = _db.get_ritual_today(yesterday_str)
    if yesterday_ritual and yesterday_ritual.get("outcome") == "survived" and phoenix_streak == 0:
        t = "Le streak est cassé. Une nuit à côté ne définit pas ta trajectoire."
        return t, "streak_reset", _SUGGESTIONS["streak_reset"], {"streak_broken": True}

    # Workout urgency checks
    sessions = _db.get_workout_sessions(limit=14)
    if sessions:
        last_str = sessions[0].get("date", "")
        try:
            last_date = date.fromisoformat(last_str)
            days_since = (today - last_date).days
            if days_since >= 4:
                t = f"Tu n'as pas touché une barre depuis {days_since} jours."
                ctx = {"jours_sans_séance": days_since, "dernière_séance": last_str}
                return t, "workout_gap", _SUGGESTIONS["workout_gap"], ctx
        except ValueError:
            pass

        week_start = (today - timedelta(days=today.weekday())).isoformat()
        this_week = [s for s in sessions if s.get("date", "") >= week_start]
        if not this_week and today.weekday() >= 2:
            day_names = {2: "mercredi", 3: "jeudi", 4: "vendredi", 5: "samedi", 6: "dimanche"}
            t = f"Zéro séance cette semaine — on est {day_names.get(today.weekday(), '')}."
            ctx = {"jour_semaine": day_names.get(today.weekday(), ""), "séances_cette_semaine": 0}
            return t, "workout_skip", _SUGGESTIONS["workout_skip"], ctx

        recent_rpes = [s["rpe"] for s in sessions[:7] if s.get("rpe")]
        older_rpes  = [s["rpe"] for s in sessions[7:] if s.get("rpe")]
        if len(recent_rpes) >= 3 and len(older_rpes) >= 3:
            avg_r = sum(recent_rpes) / len(recent_rpes)
            avg_o = sum(older_rpes) / len(older_rpes)
            if avg_r > avg_o * 1.12:
                t = (f"Ton RPE monte depuis 2 semaines "
                     f"({avg_r:.1f} vs {avg_o:.1f}). La fatigue s'accumule sans que tu le voies.")
                ctx = {"RPE_récent_moyen": round(avg_r, 1), "RPE_précédent_moyen": round(avg_o, 1)}
                return t, "stress_rising", _SUGGESTIONS["stress_rising"], ctx

    # C2: PSS-4 high stress
    try:
        pss_records = _db.get_pss_records(pss_type="pss4", limit=3)
        if pss_records:
            latest_pss = pss_records[0].get("score", 0) or 0
            if latest_pss >= 12:
                t = f"Ton PSS est à {latest_pss}. La charge mentale précède toujours la régression physique."
                ctx = {"pss_score": latest_pss}
                return t, "pss_high", _SUGGESTIONS["pss_high"], ctx
    except Exception:
        pass

    # C1: Heavy or recovery session today
    try:
        from planner import get_today
        session_today = get_today()
        HEAVY = {"Push A", "Push B", "Pull A", "Pull B + Full Body", "Legs"}
        LIGHT = {"Yoga / Tai Chi", "Recovery"}
        if session_today in HEAVY:
            t = f"Séance {session_today} aujourd'hui. Tu ne viens pas pour faire semblant."
            ctx = {"session": session_today, "type": "heavy"}
            return t, "session_heavy", _SUGGESTIONS["session_heavy"], ctx
        if session_today in LIGHT:
            t = "Jour de récupération. Récupérer activement, c'est aussi de l'entraînement."
            ctx = {"session": session_today, "type": "recovery"}
            return t, "recovery_day", _SUGGESTIONS["recovery_day"], ctx
    except Exception:
        pass

    # Sleep debt
    recovery = _db.get_recovery_logs(limit=7)
    sleep_vals = [r["sleep_hours"] for r in recovery if r.get("sleep_hours")]
    if len(sleep_vals) >= 3:
        avg_sleep = sum(sleep_vals) / len(sleep_vals)
        if avg_sleep < 6.5:
            t = (f"Tu dors {avg_sleep:.1f}h en moyenne cette semaine. "
                 f"Le manque de sommeil efface tes progrès.")
            ctx = {"sommeil_moyen_h": round(avg_sleep, 1), "jours_mesurés": len(sleep_vals)}
            return t, "sleep_debt", _SUGGESTIONS["sleep_debt"], ctx

    # Protein gap
    nutrition_settings = _db.get_nutrition_settings()
    protein_goal = nutrition_settings.get("proteines") or nutrition_settings.get("protein_g")
    if protein_goal and protein_goal > 0:
        nutrition_days = _db.get_nutrition_entries_recent(7)
        if len(nutrition_days) >= 4:
            below = sum(1 for d in nutrition_days if d.get("proteines", 0) < protein_goal * 0.80)
            if below >= 4:
                t = (f"Tu n'as pas atteint tes protéines ({int(protein_goal)}g) "
                     f"depuis {below} des 7 derniers jours.")
                ctx = {
                    "objectif_protéines_g": int(protein_goal),
                    "jours_sous_objectif": below,
                    "jours_total_mesurés": len(nutrition_days),
                }
                return t, "protein_gap", _SUGGESTIONS["protein_gap"], ctx

    text, ttype = random.choice(_DEFAULT_TRUTHS)
    return text, ttype, _SUGGESTIONS["default"], {}


# ── Claude truth generation ───────────────────────────────────────────────────

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
    try:
        import pattern_engine as _pe
        result = _pe.get_daily_pattern()
        daily = result.get("daily")
        if daily and daily.get("headline"):
            return daily["headline"]
    except Exception:
        pass
    return None


def _generate_truth_with_claude(truth_type: str, fallback_truth: str, context_data: dict) -> str:
    import os
    try:
        import anthropic
        api_key = os.environ.get("ANTHROPIC_API_KEY", "")
        if not api_key:
            return fallback_truth

        lines = [f"Type de vérité : {truth_type}"]
        for k, v in context_data.items():
            lines.append(f"{k} : {v}")
        pattern_headline = _get_top_pattern_headline()
        if pattern_headline:
            lines.append(f"pattern_du_jour : {pattern_headline}")

        client = anthropic.Anthropic(api_key=api_key, timeout=7.0)
        msg = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=120,
            system=_TRUTH_SYSTEM,
            messages=[{"role": "user", "content": "\n".join(lines)}],
        )
        generated = (msg.content[0].text or "").strip()
        if generated and len(generated) > 10:
            return generated
    except Exception as e:
        logger.warning("Claude API failed for truth generation: %s", e)  # A4
    return fallback_truth


# ── Phoenix streak computation ───────────────────────────────────────────────

def _compute_phoenix() -> tuple[int, int, int]:
    import db as _db
    rows = _db.get_ritual_history(limit=365)
    if not rows:
        return 0, 0, 0

    total_burned = sum(1 for r in rows if r.get("outcome") == "burned")

    completed = [r for r in rows if r.get("outcome") in ("burned", "survived")]
    current = 0
    for r in completed:
        if r.get("outcome") == "burned":
            current += 1
        else:
            break

    best, run = 0, 0
    for r in sorted(rows, key=lambda r: r.get("date", "")):
        if r.get("outcome") == "burned":
            run += 1
            best = max(best, run)
        elif r.get("outcome") == "survived":
            run = 0

    return current, best, total_burned


# ── Routes ───────────────────────────────────────────────────────────────────

@ritual_bp.route("/api/ritual/today")
def api_ritual_today():
    import db as _db

    today_str           = _today_mtl().isoformat()
    yesterday_str        = (_today_mtl() - timedelta(days=1)).isoformat()
    existing             = _db.get_ritual_today(today_str)
    yesterday_ritual     = _db.get_ritual_today(yesterday_str)
    yesterday_intention  = (yesterday_ritual or {}).get("tomorrow_intention")
    yesterday_outcome    = (yesterday_ritual or {}).get("outcome")
    yesterday_evening_at = (yesterday_ritual or {}).get("evening_at")
    streak, best, total = _compute_phoenix()
    raw_demons          = _db.get_ritual_demons()
    demons              = _enrich_carry_counts(raw_demons)  # A1

    if existing:
        ttype = existing.get("truth_type", "default")
        # streak_elevation supprimé — remplacer toute truth en cache de ce type
        if ttype == "streak_elevation":
            new_truth, ttype, _, ctx = _build_truth(phoenix_streak=streak)
            new_truth = _generate_truth_with_claude(ttype, new_truth, ctx)
            try:
                _db.upsert_ritual({**existing, "truth": new_truth, "truth_type": ttype})
            except Exception:
                pass
            existing = {**existing, "truth": new_truth, "truth_type": ttype}
        suggestions = _SUGGESTIONS.get(ttype, _SUGGESTIONS["default"])
        # Surface oldest demon even on existing
        carried_intention = existing.get("carried_intention")
        carried_from      = existing.get("carried_from")
        carry_count       = existing.get("carry_count", 0)
        if not carried_intention:
            survived_demons = [d for d in demons if d.get("carry_count", 0) > 0]
            if survived_demons:
                oldest            = sorted(survived_demons, key=lambda d: d.get("date", ""))[0]
                carried_intention = oldest.get("intention")
                carried_from      = oldest.get("date")
                carry_count       = oldest.get("carry_count", 0)
        return jsonify({
            **existing,
            "carry_count":           carry_count,
            "carried_from":          carried_from,
            "carried_intention":     carried_intention,
            "suggestions":           suggestions,
            "phoenix_streak":        streak,
            "phoenix_best":          best,
            "phoenix_total_burned":  total,
            "demons":                demons,
            "yesterday_intention":   yesterday_intention,
            "yesterday_outcome":     yesterday_outcome,
            "yesterday_evening_at":  yesterday_evening_at,
        })

    truth, ttype, suggestions, ctx = _build_truth(phoenix_streak=streak)
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

    try:
        _db.upsert_ritual({
            "date":         today_str,
            "truth":        truth,
            "truth_type":   ttype,
            "carry_count":  carry_count,
            "carried_from": carried_from,
        })
    except Exception:
        pass

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
        "yesterday_intention":   yesterday_intention,
        "yesterday_outcome":     yesterday_outcome,
        "yesterday_evening_at":  yesterday_evening_at,
        "morning_ack":           None,
    })


@ritual_bp.route("/api/ritual/morning", methods=["POST"])
def api_ritual_morning():
    import db as _db

    data      = request.get_json(silent=True) or {}
    intention = (data.get("intention") or "").strip()
    if not intention:
        return jsonify({"error": "intention is required"}), 400

    today_str = _today_mtl().isoformat()
    now_iso   = datetime.now(timezone.utc).isoformat()
    existing  = _db.get_ritual_today(today_str) or {}

    if existing.get("truth"):
        truth, ttype = existing["truth"], existing["truth_type"]
    else:
        streak, _, _ = _compute_phoenix()
        truth, ttype, _, ctx = _build_truth(phoenix_streak=streak)
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

    today_str = _today_mtl().isoformat()
    existing  = _db.get_ritual_today(today_str)
    if not existing or not existing.get("intention"):
        return jsonify({"error": "Complete the morning ritual first"}), 400

    now_iso              = datetime.now(timezone.utc).isoformat()
    reflection           = (data.get("reflection") or "").strip() or None
    winddown             = data.get("winddown_done")
    cold                 = data.get("cold_done")
    gratitude            = (data.get("gratitude") or "").strip() or None
    tomorrow_intention   = (data.get("tomorrow_intention") or "").strip() or None

    patch = {**existing, "outcome": outcome, "evening_at": now_iso}
    if reflection is not None:
        patch["reflection"] = reflection
    if winddown is not None:
        patch["winddown_done"] = bool(winddown)
    if cold is not None:
        patch["cold_done"] = bool(cold)
    if gratitude:
        patch["gratitude"] = gratitude
    if tomorrow_intention is not None:
        patch["tomorrow_intention"] = tomorrow_intention

    ok = _db.upsert_ritual(patch)
    if not ok:
        return jsonify({"error": "Erreur base de données"}), 500

    streak, best, total = _compute_phoenix()

    # C9: detect if intention was honored via session data
    intention_matched_session = False
    try:
        sessions_today = [s for s in _db.get_workout_sessions(limit=5) if s.get("date") == today_str]
        if sessions_today and existing.get("intention"):
            intention_lower = existing["intention"].lower()
            workout_words = {"séance", "squat", "bench", "deadlift", "soulevé", "soulevée",
                             "entraîne", "salle", "musculation", "barre", "poids", "reps",
                             "sets", "push", "pull", "legs", "press", "curl", "row"}
            if any(w in intention_lower for w in workout_words):
                intention_matched_session = True
    except Exception:
        pass

    return jsonify({
        "ok":                        True,
        "outcome":                   outcome,
        "phoenix_streak":            streak,
        "phoenix_best":              best,
        "phoenix_total_burned":      total,
        "intention_matched_session": intention_matched_session,
    })


@ritual_bp.route("/api/ritual/streak")
def api_ritual_streak():
    streak, best, total = _compute_phoenix()
    return jsonify({
        "phoenix_streak":       streak,
        "phoenix_best":         best,
        "phoenix_total_burned": total,
    })


@ritual_bp.route("/api/ritual/checklist", methods=["POST"])
def api_ritual_checklist():
    """Update morning micro-ritual checklist items (D)."""
    import db as _db

    data = request.get_json(silent=True) or {}
    today_str = _today_mtl().isoformat()
    existing  = _db.get_ritual_today(today_str) or {"date": today_str}

    allowed = {"weight_logged", "hydration_done", "mobility_done", "protein_done", "morning_ack"}
    patch = {k: bool(data[k]) for k in allowed if k in data}
    if not patch:
        return jsonify({"error": "no checklist fields provided"}), 400

    ok = _db.upsert_ritual({**existing, **patch})
    return jsonify({"ok": ok, "updated": list(patch.keys())})


@ritual_bp.route("/api/ritual/stats")
def api_ritual_stats():
    """Ritual completion & burn rates + weekly breakdown (F3, G1, G2, G7)."""
    import db as _db

    today   = _today_mtl()
    history = _db.get_ritual_history(limit=365)
    streak, best, total = _compute_phoenix()

    def _completion_rate(days: int) -> float:
        cutoff = (today - timedelta(days=days)).isoformat()
        recent = [r for r in history if r.get("date", "") >= cutoff]
        if not recent:
            return 0.0
        completed = sum(1 for r in recent if r.get("outcome") in ("burned", "survived"))
        return round(completed / days, 3)

    def _burn_rate(days: int) -> float:
        cutoff  = (today - timedelta(days=days)).isoformat()
        recent  = [r for r in history if r.get("date", "") >= cutoff and r.get("outcome")]
        if not recent:
            return 0.0
        burned = sum(1 for r in recent if r.get("outcome") == "burned")
        return round(burned / len(recent), 3)

    # Last 8 weeks breakdown
    weekly = []
    for i in range(7, -1, -1):
        wk_start = today - timedelta(days=today.weekday() + 7 * i)
        wk_end   = wk_start + timedelta(days=6)
        wk_rows  = [
            r for r in history
            if wk_start.isoformat() <= r.get("date", "") <= wk_end.isoformat()
        ]
        weekly.append({
            "week":      wk_start.isoformat(),
            "completed": sum(1 for r in wk_rows if r.get("outcome") in ("burned", "survived")),
            "burned":    sum(1 for r in wk_rows if r.get("outcome") == "burned"),
        })

    return jsonify({
        "completion_rate_7d":   _completion_rate(7),
        "burn_rate_7d":         _burn_rate(7),
        "completion_rate_30d":  _completion_rate(30),
        "burn_rate_30d":        _burn_rate(30),
        "phoenix_streak":       streak,
        "phoenix_best":         best,
        "phoenix_total_burned": total,
        "weekly_completions":   weekly,
    })


@ritual_bp.route("/api/ritual/correlations")
def api_ritual_correlations():
    """Burn vs RPE and burn vs sleep correlations (C7, C8)."""
    import db as _db

    history    = _db.get_ritual_history(limit=365)
    sessions   = _db.get_workout_sessions(limit=365)
    recovery   = _db.get_recovery_logs(limit=365)

    ritual_by_date   = {r["date"]: r.get("outcome") for r in history}
    session_by_date  = {s["date"]: s for s in sessions}
    recovery_by_date = {r["date"]: r for r in recovery}

    burn_rpes, survive_rpes   = [], []
    burn_sleep, survive_sleep = [], []

    for r_date, outcome in ritual_by_date.items():
        if not outcome:
            continue
        try:
            next_date = (date.fromisoformat(r_date) + timedelta(days=1)).isoformat()
        except Exception:
            continue

        next_s = session_by_date.get(next_date)
        if next_s and next_s.get("rpe"):
            rpe = float(next_s["rpe"])
            (burn_rpes if outcome == "burned" else survive_rpes).append(rpe)

        next_r = recovery_by_date.get(next_date)
        if next_r and next_r.get("sleep_hours"):
            sl = float(next_r["sleep_hours"])
            (burn_sleep if outcome == "burned" else survive_sleep).append(sl)

    def _avg(lst: list) -> float | None:
        return round(sum(lst) / len(lst), 2) if lst else None

    return jsonify({
        "burn_vs_rpe": {
            "burn_next_rpe":    _avg(burn_rpes),
            "survive_next_rpe": _avg(survive_rpes),
            "n_burn":    len(burn_rpes),
            "n_survive": len(survive_rpes),
        },
        "burn_vs_sleep": {
            "burn_next_sleep":    _avg(burn_sleep),
            "survive_next_sleep": _avg(survive_sleep),
            "n_burn":    len(burn_sleep),
            "n_survive": len(survive_sleep),
        },
    })


@ritual_bp.route("/api/ritual/kill-demon", methods=["POST"])
def api_ritual_kill_demon():
    """Kill a past survived intention directly without going through evening ritual."""
    import db as _db

    data = request.get_json(silent=True) or {}
    demon_date = (data.get("date") or "").strip()
    if not demon_date:
        return jsonify({"error": "date is required"}), 400

    existing = _db.get_ritual_today(demon_date)
    if not existing:
        return jsonify({"error": "Ritual not found for this date"}), 404
    if existing.get("outcome") != "survived":
        return jsonify({"error": "This intention is not in survived state"}), 400

    now_iso = datetime.now(timezone.utc).isoformat()
    patch = {**existing, "outcome": "burned"}
    if not patch.get("evening_at"):
        patch["evening_at"] = now_iso

    ok = _db.upsert_ritual(patch)
    if not ok:
        return jsonify({"error": "Erreur base de données"}), 500

    streak, best, total = _compute_phoenix()
    return jsonify({
        "ok": True,
        "date": demon_date,
        "phoenix_streak": streak,
        "phoenix_best": best,
        "phoenix_total_burned": total,
    })


@ritual_bp.route("/api/ritual/history-full")
def api_ritual_history_full():
    """Full intention history for biography page (F1)."""
    import db as _db

    limit  = min(int(request.args.get("limit", 90)), 365)
    offset = int(request.args.get("offset", 0))
    rows   = _db.get_ritual_history_full(limit=limit, offset=offset)
    total  = _db.count_ritual_entries()

    return jsonify({"entries": rows, "total": total, "limit": limit, "offset": offset})
