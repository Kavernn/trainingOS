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

def _build_truth() -> tuple[str, str, list[str]]:
    """Return (truth_text, truth_type, suggestions[3]) based on user data."""
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
                return t, "workout_gap", _SUGGESTIONS["workout_gap"]
        except ValueError:
            pass

        # No session yet this week (Wed+) ───────────────────────────────────
        week_start = (today - timedelta(days=today.weekday())).isoformat()
        this_week  = [s for s in sessions if s.get("date", "") >= week_start]
        if not this_week and today.weekday() >= 2:
            day_names = {2: "mercredi", 3: "jeudi", 4: "vendredi", 5: "samedi", 6: "dimanche"}
            t = f"Zéro séance cette semaine — on est {day_names.get(today.weekday(), '')}."
            return t, "workout_skip", _SUGGESTIONS["workout_skip"]

        # RPE rising trend ───────────────────────────────────────────────────
        recent_rpes = [s["rpe"] for s in sessions[:7]  if s.get("rpe")]
        older_rpes  = [s["rpe"] for s in sessions[7:]  if s.get("rpe")]
        if len(recent_rpes) >= 3 and len(older_rpes) >= 3:
            avg_r = sum(recent_rpes) / len(recent_rpes)
            avg_o = sum(older_rpes)  / len(older_rpes)
            if avg_r > avg_o * 1.12:
                t = (f"Ton RPE monte depuis 2 semaines "
                     f"({avg_r:.1f} vs {avg_o:.1f}). La fatigue s'accumule sans que tu le voies.")
                return t, "stress_rising", _SUGGESTIONS["stress_rising"]

    # 2. Sleep debt ──────────────────────────────────────────────────────────
    recovery   = _db.get_recovery_logs(limit=7)
    sleep_vals = [r["sleep_hours"] for r in recovery if r.get("sleep_hours")]
    if len(sleep_vals) >= 3:
        avg_sleep = sum(sleep_vals) / len(sleep_vals)
        if avg_sleep < 6.5:
            t = (f"Tu dors {avg_sleep:.1f}h en moyenne cette semaine. "
                 f"Le manque de sommeil efface tes progrès.")
            return t, "sleep_debt", _SUGGESTIONS["sleep_debt"]

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
                return t, "protein_gap", _SUGGESTIONS["protein_gap"]

    # 4. Default rotation ────────────────────────────────────────────────────
    text, ttype = random.choice(_DEFAULT_TRUTHS)
    return text, ttype, _SUGGESTIONS["default"]


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
    truth, ttype, suggestions = _build_truth()

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
        truth, ttype, _ = _build_truth()

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
