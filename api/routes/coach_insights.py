from flask import Blueprint, jsonify, request
import logging
from utils import _today_mtl, _hour_mtl

logger = logging.getLogger("trainingos")

coach_insights_bp = Blueprint("coach_insights", __name__)


# ── Helper ────────────────────────────────────────────────────────────────────

def _insight(type_, icon, title, body, source, action, priority):
    return jsonify({
        "type": type_, "icon": icon, "title": title,
        "body": body, "source": source, "action": action,
        "priority": priority,
    })


# ── GET /api/coach/daily_insight ──────────────────────────────────────────────
# Retourne l'insight le plus important du moment.
# Ordre de priorité : P1 (alertes) → P2 (opportunités) → P3 (programme) → P4 (IA)

@coach_insights_bp.route("/api/coach/daily_insight")
def api_daily_insight():
    from datetime import date as date_cls, timedelta
    import db as _db

    today_str = _today_mtl()
    today = date_cls.fromisoformat(today_str)

    # ── P1a — ACWR > 1.3 ─────────────────────────────────────────────────────
    try:
        from acwr import calc_acwr
        acwr_data = calc_acwr()
        ratio = acwr_data.get("ratio") or acwr_data.get("acwr")
        if ratio and ratio > 1.3:
            return _insight(
                "alert", "exclamationmark.triangle.fill",
                "Sur-charge détectée",
                f"ACWR à {ratio:.2f} — réduis le volume cette semaine pour éviter une blessure.",
                f"ACWR · {ratio:.2f}", "stats", 1,
            )
    except Exception:
        pass

    # ── P1b — Plateau actif (severity critical ou warning) ───────────────────
    try:
        from plateau import detect
        active = [
            a for a in (detect().get("alerts") or [])
            if a.get("severity") in ("critical", "warning")
            and a.get("status") not in ("dismissed", "completed")
        ]
        if active:
            p = active[0]
            ex = p.get("exercise_name", "exercice")
            weeks = p.get("plateau_weeks") or 0
            icon = (
                "exclamationmark.circle.fill"
                if p.get("severity") == "critical"
                else "arrow.right.circle.fill"
            )
            return _insight(
                "alert", icon,
                f"Stagnation — {ex}",
                f"Aucune progression depuis {weeks} semaine{'s' if weeks != 1 else ''} sur {ex}. Temps de changer d'approche.",
                ex, "seance", 1,
            )
    except Exception:
        pass

    # ── P1c — Protéines < 80 % objectif depuis 3j+ ───────────────────────────
    try:
        from nutrition import load_settings as _nutr_cfg
        cfg = _nutr_cfg() or {}
        prot_target = (
            cfg.get("protein_limit") or cfg.get("protein_target") or
            cfg.get("proteines_limit") or cfg.get("proteines_target") or 0
        )
        if prot_target > 0:
            recent = _db.get_nutrition_entries_recent(n=3)
            if len(recent) >= 3:
                below = [n for n in recent if (n.get("proteines") or 0) < prot_target * 0.80]
                if len(below) >= 3:
                    avg_p = round(sum(n.get("proteines", 0) for n in recent) / len(recent))
                    return _insight(
                        "alert", "fork.knife",
                        "Déficit protéines prolongé",
                        f"Moyenne {avg_p}g/jour sur 3 jours — objectif {int(prot_target)}g. La récupération est compromise.",
                        f"Nutrition · {avg_p}g moy.", "stats", 1,
                    )
    except Exception:
        pass

    # ── P1d — Sommeil < 6h depuis 3j+ ────────────────────────────────────────
    try:
        from health_data import get_weekly_health_summary
        sleep_3d = [
            d["sleep_duration"]
            for d in get_weekly_health_summary(days=3)
            if d.get("sleep_duration") is not None
        ]
        if len(sleep_3d) >= 3 and all(s < 6.0 for s in sleep_3d):
            avg_sleep = round(sum(sleep_3d) / len(sleep_3d), 1)
            return _insight(
                "alert", "moon.fill",
                "Dette de sommeil accumulée",
                f"Moins de 6h par nuit depuis 3 jours (moy. {avg_sleep}h). Performance et récupération impactées.",
                f"Sommeil · {avg_sleep}h moy.", "stats", 1,
            )
    except Exception:
        pass

    # ── P2a — Record à portée (< 5 % du PR historique) ───────────────────────
    try:
        import db as _db
        for p in _db.get_exercise_prs():
            if p["baseline_count"] < 3:
                continue
            pr      = p["pr_weight_lbs"]
            current = p["current_weight"]
            name    = p["exercise_name"]
            if 0 < current < pr and current >= pr * 0.95:
                gap = round(pr - current, 1)
                return _insight(
                    "opportunity", "bolt.fill",
                    "Record à portée",
                    f"Tu es à {gap} lbs de ton record sur {name}. C'est le moment de tenter.",
                    f"{name} · PR {pr:.0f} lbs", "seance", 2,
                )
    except Exception:
        pass

    # ── P2b — HRV au-dessus de la baseline depuis 3j+ ────────────────────────
    try:
        from health_data import get_weekly_health_summary
        hrv_vals = [
            d["hrv"]
            for d in get_weekly_health_summary(days=14)
            if d.get("hrv") is not None
        ]
        if len(hrv_vals) >= 7:
            baseline = sum(hrv_vals[3:]) / len(hrv_vals[3:])
            recent_3 = hrv_vals[:3]
            if baseline > 0 and len(recent_3) >= 3 and all(h > baseline * 1.05 for h in recent_3):
                avg_hrv = round(sum(recent_3) / len(recent_3), 1)
                return _insight(
                    "opportunity", "waveform.path.ecg",
                    "Fenêtre de surcharge",
                    f"HRV à {avg_hrv} ces 3 derniers jours — au-dessus de ta baseline. Profite-en pour augmenter l'intensité.",
                    f"HRV · {avg_hrv} moy.", "seance", 2,
                )
    except Exception:
        pass

    # ── P2c — Semaine exceptionnelle (5+ séances complétées) ─────────────────
    try:
        from datetime import timedelta
        week_start = (today - timedelta(days=6)).isoformat()
        count_7d = sum(
            1 for s in _db.get_workout_sessions(limit=30)
            if s.get("date") and str(s["date"]) >= week_start
            and (s.get("completed") or s.get("rpe") is not None)
        )
        if count_7d >= 5:
            return _insight(
                "opportunity", "checkmark.seal.fill",
                "Excellente semaine",
                f"{count_7d} séances complétées cette semaine. Tu es en avance sur ton objectif.",
                f"{count_7d} séances · 7j", "stats", 2,
            )
    except Exception:
        pass

    # ── P3 — Absence prolongée (5j+ sans séance) ─────────────────────────────
    try:
        completed = [
            s for s in _db.get_workout_sessions(limit=10)
            if s.get("completed") or s.get("rpe") is not None
        ]
        if completed:
            last_date = date_cls.fromisoformat(str(completed[0]["date"]))
            days_since = (today - last_date).days
            if days_since >= 5:
                from deload import load_deload_state
                deload = load_deload_state()
                if deload.get("active"):
                    ends_at = deload.get("ends_at") or "bientôt"
                    return _insight(
                        "opportunity", "bed.double.fill",
                        "Décharge volontaire en cours",
                        f"Repos intentionnel actif depuis {deload.get('started_at', '?')} — reprise prévue {ends_at}. Récupère bien.",
                        f"Décharge · {days_since}j de repos", "stats", 3,
                    )
                return _insight(
                    "programme", "calendar.badge.exclamationmark",
                    f"{days_since} jours sans séance",
                    "Une reprise progressive aujourd'hui maintiendra ta progression. Volume réduit recommandé.",
                    f"Dernière séance · {last_date.strftime('%d %b')}", "seance", 3,
                )
    except Exception:
        pass

    # ── P4 — Fallback IA (Haiku, 1 phrase) ───────────────────────────────────
    try:
        import os
        import anthropic as _anthropic
        api_key = os.environ.get("ANTHROPIC_API_KEY", "")
        if api_key:
            from morning_brief import get_morning_brief
            brief = get_morning_brief()
            ctx = "\n".join([
                f"LSS: {brief.get('lss', '?')}/100",
                f"Séance prévue: {brief.get('session_today', '?')}",
                f"Recommandation système: {brief.get('recommendation', '?')}",
            ])
            msg = _anthropic.Anthropic(api_key=api_key).messages.create(
                model="claude-haiku-4-5-20251001",
                max_tokens=60,
                system=(
                    "Tu es un coach sportif. Génère UN insight d'entraînement en 1 phrase (max 15 mots). "
                    "Direct, basé sur les données, actionnable. Tutoiement. Français. Pas de ponctuation superflue."
                ),
                messages=[{"role": "user", "content": ctx}],
            )
            return _insight(
                "ai_fallback", "brain.head.profile",
                "Insight du jour",
                msg.content[0].text.strip(),
                "Coach IA", "coach", 4,
            )
    except Exception:
        pass

    return jsonify({
        "type": "none", "icon": "", "title": "", "body": "",
        "source": "", "action": "", "priority": 0,
    })


# ── GET /api/coach/post_session ───────────────────────────────────────────────
# Feedback contextuel pour la séance complétée du jour.
# Paramètre optionnel : ?date=YYYY-MM-DD (défaut = aujourd'hui)

@coach_insights_bp.route("/api/coach/post_session")
def api_post_session():
    import db as _db

    target_date = request.args.get("date") or _today_mtl()

    try:
        session = _db.get_workout_session(target_date)
        if not session or not (session.get("completed") or session.get("rpe") is not None):
            return jsonify({"error": "Aucune séance complétée pour cette date"}), 404
    except Exception as e:
        logger.error("post_session get_workout_session: %s", e)
        return jsonify({"error": "Erreur lors de la récupération de la séance"}), 500

    session_rpe  = session.get("rpe")
    session_name = session.get("session_name") or session.get("session_type") or "Séance"
    session_id   = str(session.get("id") or "")

    rpe_interpretation = _interpret_rpe(session_rpe)
    volume_delta_pct   = _compute_volume_delta(session_id, session_name, session_rpe, target_date)
    nutrition_advice   = _post_session_nutrition_advice()

    return jsonify({
        "volume_delta_pct":  volume_delta_pct,
        "avg_rpe":           session_rpe,
        "rpe_interpretation": rpe_interpretation,
        "nutrition_advice":  nutrition_advice,
        "session_id":        session_id,
        "session_name":      session_name,
    })


def _interpret_rpe(rpe):
    if rpe is None:
        return "Intensité non enregistrée"
    if rpe <= 4:
        return "Séance légère — récupération active"
    if rpe <= 6:
        return "Intensité modérée — bien équilibré"
    if rpe <= 7.5:
        return "Intensité correcte — dans la zone cible"
    if rpe <= 8.5:
        return "Séance intensive — prévois une bonne récupération"
    return "Effort maximal — repos prioritaire"


def _compute_volume_delta(session_id, session_name, session_rpe, target_date):
    """Compare RPE de la séance actuelle vs baseline même type."""
    try:
        import db as _db
        all_sessions = _db.get_workout_sessions(limit=60)
        same_type = [
            s for s in all_sessions
            if (s.get("session_name") or s.get("session_type")) == session_name
            and str(s.get("date")) != target_date
            and s.get("rpe") is not None
        ]
        if len(same_type) >= 3 and session_rpe is not None:
            sample = same_type[:8]
            baseline = sum(s["rpe"] for s in sample) / len(sample)
            if baseline > 0:
                # Delta RPE positif = effort plus élevé que baseline
                return round((session_rpe - baseline) / baseline * 100)
    except Exception:
        pass
    return None


def _post_session_nutrition_advice():
    """Conseil nutritionnel post-séance basé sur les macros du jour."""
    try:
        import db as _db
        from nutrition import load_settings as _nutr_cfg
        from datetime import datetime

        entries = _db.get_nutrition_entries_recent(n=1)
        if not entries:
            return "Enregistre ta nutrition post-séance pour optimiser la récupération."

        entry = entries[0]
        proteines = entry.get("proteines") or 0
        calories  = entry.get("calories") or 0
        hour      = _hour_mtl()

        cfg = _nutr_cfg() or {}
        prot_target = (
            cfg.get("protein_limit") or cfg.get("protein_target") or
            cfg.get("proteines_limit") or cfg.get("proteines_target") or 0
        )
        cal_target = cfg.get("calorie_limit") or 0

        if prot_target > 0 and proteines < prot_target * 0.6:
            remaining = int(prot_target - proteines)
            return f"Il te reste {remaining}g de protéines à atteindre aujourd'hui. Priorité post-séance."
        if cal_target > 0 and calories < cal_target * 0.5 and hour >= 16:
            return "Apport calorique faible aujourd'hui — recharge avant la fin de la journée."
        if hour < 14:
            return "Recharge en protéines dans les 30 min pour optimiser la synthèse musculaire."
        return "Bonne récupération. Hydrate-toi et atteins ton objectif protéines avant ce soir."
    except Exception:
        return "Pense à te recharger en protéines après ta séance."
