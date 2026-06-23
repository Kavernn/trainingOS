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
    engagement_streak = brief_data.get("engagement_streak", 0)
    return {
        "recovery_needed": rec in ("reduce", "defer") or flags.get("hrv_drop") or flags.get("sleep_deprivation") or flags.get("training_overload"),
        "momentum": engagement_streak >= 7 and rec == "go",
    }


def _build_context(brief_data: dict, extra: dict | None = None) -> str:
    """Compose a compact predictive context string for Claude."""
    extra = extra or {}
    lss = brief_data.get("lss")
    rec = brief_data.get("recommendation", "go")
    session = brief_data.get("session_today", "")
    intensity = brief_data.get("session_intensity", "")
    adjustments = brief_data.get("adjustments", [])
    flags = brief_data.get("flags", {})
    engagement_streak = brief_data.get("engagement_streak", 0)

    lines = []

    # CALENDRIER
    cal = [f"{session} ({intensity})"]
    next_s = extra.get("next_session")
    if next_s:
        cal.append(f"Demain: {next_s['name']} ({next_s['intensity']})")
    day_after = extra.get("day_after_session")
    if day_after:
        cal.append(f"J+2: {day_after['name']}")
    lines.append("Calendrier: " + " | ".join(cal))

    # READINESS
    if lss is not None:
        lines.append(f"Readiness: {lss}/100 — {rec}")

    # TRAJECTOIRES — HRV
    hrv = extra.get("hrv")
    if hrv and hrv.get("today_ms") is not None:
        pct = hrv.get("pct_vs_baseline")
        sign = "+" if pct is not None and pct >= 0 else ""
        pct_str = f" ({sign}{pct}% vs baseline)" if pct is not None else ""
        trend_str = f", tendance {hrv['trend']}" if hrv.get("trend") else ""
        streak_str = (
            f", {hrv['consecutive_low_days']}j consécutifs sous baseline"
            if hrv.get("streak_alert") else ""
        )
        lines.append(f"HRV: {hrv['today_ms']}ms{pct_str}{trend_str}{streak_str}")
    elif flags.get("hrv_drop"):
        lines.append("Signal: HRV en baisse")

    # TRAJECTOIRES — ACWR
    acwr = extra.get("acwr")
    if acwr:
        _zone_fr = {"optimal": "zone optimale", "under": "sous-charge",
                    "caution": "attention", "danger": "surcharge"}
        zone_str = _zone_fr.get(acwr.get("zone_code", ""), "")
        delta = acwr.get("delta_pct")
        sign = "+" if delta is not None and delta >= 0 else ""
        delta_str = f" ({sign}{delta}% vs sem. précédente)" if delta is not None else ""
        lines.append(f"ACWR: {acwr['ratio']:.2f} {zone_str}{delta_str}")
    elif flags.get("training_overload"):
        lines.append("Signal: surcharge cumulée")

    # TRAJECTOIRES — Sommeil
    sd = extra.get("sleep_debt")
    if sd:
        _trend_fr = {"creuser": "s'aggrave", "stable": "stable", "rembourser": "se rembourse"}
        trend_str = _trend_fr.get(sd.get("trend", "stable"), "")
        ntr = sd.get("nights_to_recover")
        ntr_str = f", remboursement: {ntr} nuit{'s' if ntr != 1 else ''}" if ntr else ""
        if (sd.get("debt_7d") or 0) > 0:
            lines.append(f"Sommeil: dette {sd['debt_7d']}h/7j, {trend_str}{ntr_str}")
        else:
            lines.append("Sommeil: excédent (pas de dette)")
    elif flags.get("sleep_deprivation"):
        lines.append("Signal: sommeil insuffisant")

    # OPPORTUNITÉS — PR window
    pr_win = extra.get("pr_window")
    if pr_win:
        lines.append(f"Fenêtre PR: {pr_win['exercise']} à {pr_win['gap_lbs']} lbs du record")

    # OPPORTUNITÉS — Bonne lancée (O4 sans phoenix_engine)
    acwr_ok = not acwr or acwr.get("zone_code") not in ("caution", "danger")
    sleep_ok = not sd or sd.get("trend") != "creuser"
    if engagement_streak >= 7 and acwr_ok and sleep_ok:
        lines.append(f"Lancée: {engagement_streak} jours d'engagements tenus consécutifs, charge équilibrée")

    if adjustments:
        lines.append("Ajustements: " + " | ".join(adjustments))

    context = "\n".join(lines)
    if len(context.encode()) > 3072:
        logger.warning("daily_brief: context %d bytes dépasse 3KB", len(context.encode()))
    return context


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
    if flags.get("hrv_drop") or flags.get("sleep_deprivation"):
        reco.append("Ce soir : fais ta routine du soir")

    return {"use_quote": True, "mot": None, "lecture": lecture, "recommandation": reco}


def _get_predictive_context() -> dict:
    """Fetch predictive signals avec guards insufficient_data par signal.
    Chaque fetch est isolé — une erreur n'interrompt pas les autres.
    """
    result = {}

    # ACWR (omis si confidence == "low" = < 7j de données)
    try:
        from acwr import calc_acwr
        acwr = calc_acwr()
        if acwr.get("confidence") != "low":
            trend = acwr.get("trend", [])
            delta_pct = None
            if len(trend) >= 2:
                prev = trend[-2].get("ratio", 0)
                curr = trend[-1].get("ratio", 0)
                if prev > 0:
                    delta_pct = round((curr - prev) / prev * 100)
            result["acwr"] = {
                "ratio":    acwr.get("ratio"),
                "zone_code": (acwr.get("zone") or {}).get("code", "insufficient_data"),
                "delta_pct": delta_pct,
            }
    except Exception as e:
        logger.warning("predictive_context ACWR: %s", e)

    # HRV (omis si baseline_available = False, c'est-à-dire < 3j de données)
    try:
        import db as _db
        from hrv_engine import compute_hrv_analysis
        from utils import _today_mtl
        rows = _db.get_recovery_logs(limit=35)
        if rows:
            hrv = compute_hrv_analysis(rows, _today_mtl())
            if hrv.get("baseline_available") and hrv.get("today_rmssd") is not None:
                avg = hrv.get("hrv_7d_avg")
                pct = (
                    round((hrv["today_rmssd"] - avg) / avg * 100)
                    if avg and avg > 0 else None
                )
                result["hrv"] = {
                    "today_ms":             round(hrv["today_rmssd"]),
                    "pct_vs_baseline":      pct,
                    "zone":                 hrv.get("hrv_zone"),
                    "trend":                hrv.get("hrv_trend"),
                    "consecutive_low_days": hrv.get("consecutive_low_days", 0),
                    "streak_alert":         hrv.get("streak_alert", False),
                }
    except Exception as e:
        logger.warning("predictive_context HRV: %s", e)

    # Sleep debt (omis si has_data = False, c'est-à-dire logged_7d < 3)
    try:
        from sleep_debt_engine import compute as _sleep_debt
        sd = _sleep_debt()
        if sd.get("has_data"):
            result["sleep_debt"] = {
                "debt_7d":           sd.get("debt_7d"),
                "trend":             sd.get("trend"),
                "nights_to_recover": sd.get("nights_to_recover"),
            }
    except Exception as e:
        logger.warning("predictive_context sleep_debt: %s", e)

    # Séance demain + J+2 (jours absents du schedule = repos implicite)
    try:
        from planner import get_week_schedule, _montreal_now
        from morning_brief import _intensity
        schedule = get_week_schedule()
        days = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
        today_idx = _montreal_now().weekday()
        for offset, key in [(1, "next_session"), (2, "day_after_session")]:
            name = schedule.get(days[(today_idx + offset) % 7]) or "Repos"
            result[key] = {"name": name, "intensity": _intensity(name)}
    except Exception as e:
        logger.warning("predictive_context schedule: %s", e)

    # PR window (omis si baseline_count < 3 sur le lift)
    try:
        import db as _db
        for p in _db.get_exercise_prs():
            if (p.get("baseline_count") or 0) < 3:
                continue
            pr = p.get("pr_weight_lbs") or 0
            current = p.get("current_weight") or 0
            if 0 < current < pr and current >= pr * 0.95:
                result["pr_window"] = {
                    "exercise": p.get("exercise_name", ""),
                    "gap_lbs":  round(pr - current, 1),
                }
                break
    except Exception as e:
        logger.warning("predictive_context PR: %s", e)

    return result


def _call_claude(context: str, triggers: dict) -> dict:
    """Call Claude once and return parsed brief dict."""
    import anthropic as _anthropic

    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not api_key:
        raise RuntimeError("ANTHROPIC_API_KEY manquant")

    trigger_note = ""
    if triggers.get("recovery_needed"):
        trigger_note = "TRIGGER ACTIF: récupération — oriente le mot vers la récupération/patience si use_quote=false. Inclus dans recommandation: \"Ce soir : fais ta routine du soir\"."
    elif triggers.get("momentum"):
        trigger_note = "TRIGGER ACTIF: momentum — oriente le mot vers la constance/lancée si use_quote=false."

    system = (
        "Tu es le coach de performance de Vincent — gym et vie. "
        "Tu parles directement à lui, au présent, sans flatterie. "
        "Le contexte inclut des TRAJECTOIRES (tendances sur plusieurs jours, pas des valeurs ponctuelles) "
        "et un CALENDRIER (aujourd'hui + demain). "
        "Ta LECTURE croise ces tendances avec le calendrier pour projeter : "
        "'HRV en baisse 3j + séance lourde demain = tu te présentes sous-récupéré si rien ne change.' "
        "Ta RECOMMANDATION est préventive (protège demain) ou opportuniste (profite de la fenêtre). "
        "Si les données sont insuffisantes pour anticiper, dis ce que tu vois sans deviner."
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
        extra = _get_predictive_context()
        triggers = _check_triggers(brief_data)
        context = _build_context(brief_data, extra)

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
