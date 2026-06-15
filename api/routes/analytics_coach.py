from flask import Blueprint, jsonify, request
from datetime import datetime, timedelta
import logging
from utils import _today_mtl, _now_mtl

logger = logging.getLogger("trainingos")

analytics_coach_bp = Blueprint("analytics_coach", __name__)


@analytics_coach_bp.route("/api/coach/morning_brief")
def api_morning_brief():
    from morning_brief import get_morning_brief
    import db as _db
    brief = get_morning_brief()

    try:
        import os
        import anthropic as _anthropic
        api_key = os.environ.get("ANTHROPIC_API_KEY", "")
        if api_key and brief.get("lss") is not None:
            ctx_parts = [
                f"LSS (Life Stress Score): {brief['lss']:.0f}/100",
                f"Séance prévue: {brief['session_today']} (intensité: {brief['session_intensity']})",
                f"Recommandation système: {brief['recommendation']}",
            ]
            active_flags = [k for k, v in (brief.get("flags") or {}).items() if v]
            if active_flags:
                ctx_parts.append(f"Alertes: {', '.join(active_flags)}")
            if brief.get("adjustments"):
                ctx_parts.append(f"Ajustements suggérés: {', '.join(brief['adjustments'])}")
            try:
                sessions = _db.get_workout_sessions(limit=3)
                if sessions:
                    last = sessions[0]
                    ctx_parts.append(
                        f"Dernière séance: {last.get('date','?')} — "
                        f"{last.get('session_name') or last.get('session_type','?')} "
                        f"RPE {last.get('rpe','?')}/10"
                    )
            except Exception:
                pass
            try:
                nutrition = _db.get_nutrition_entries_recent(n=1)
                if nutrition:
                    n = nutrition[0]
                    ctx_parts.append(
                        f"Nutrition hier: {n.get('calories','?')} kcal, "
                        f"{n.get('proteines','?')}g protéines"
                    )
            except Exception:
                pass

            client = _anthropic.Anthropic(api_key=api_key)
            msg = client.messages.create(
                model="claude-haiku-4-5-20251001",
                max_tokens=80,
                system=(
                    "Tu es un coach sportif. En une seule phrase (max 20 mots), "
                    "génère un message d'encouragement matinal personnalisé basé sur les données. "
                    "Cite UN chiffre concret (LSS, RPE, ou intensité). "
                    "Style direct, énergisant. Tutoiement. Français uniquement. "
                    "Pas de ponctuation finale superflue."
                ),
                messages=[{"role": "user", "content": "\n".join(ctx_parts)}],
            )
            brief["message"] = msg.content[0].text.strip()
    except Exception:
        pass  # fallback to Python-generated message

    return jsonify(brief)


@analytics_coach_bp.route("/api/insights")
def api_insights():
    import db as _db
    from weights import load_weights

    weights  = load_weights()
    sessions_raw = _db.get_workout_sessions(limit=365)
    sessions = {}
    for s in sessions_raw:
        d = s.get("date")
        if not d: continue
        if s.get("completed") or s.get("rpe") is not None:
            sessions[str(d)] = s

    now      = _now_mtl()
    insights = []

    def dstr(d): return d.strftime("%Y-%m-%d")

    # 1. FATIGUE RPE — avg 7j vs 30j
    s7  = [s["rpe"] for d, s in sessions.items() if d >= dstr(now - timedelta(days=7))  and s.get("rpe")]
    s30 = [s["rpe"] for d, s in sessions.items() if d >= dstr(now - timedelta(days=30)) and s.get("rpe")]
    if len(s7) >= 2 and len(s30) >= 5:
        avg7  = sum(s7)  / len(s7)
        avg30 = sum(s30) / len(s30)
        if avg7 > avg30 + 0.8:
            insights.append({
                "type": "fatigue", "level": "warning",
                "icon": "flame.fill", "title": "Fatigue en hausse",
                "message": f"RPE moyen {avg7:.1f}/10 cette semaine vs {avg30:.1f}/10 sur 30 jours. Envisage de réduire l'intensité."
            })

    # 2. STAGNATION — même poids 4+ séances consécutives
    for ex, data in weights.items():
        hist = [e for e in (data.get("history") or []) if e.get("weight") and e.get("date")]
        if len(hist) < 4: continue
        ws = [e["weight"] for e in hist[-4:]]
        if max(ws) == min(ws) and ws[0] > 0:
            insights.append({
                "type": "stagnation", "level": "info",
                "icon": "chart.line.flattrend.xyaxis", "title": f"Plateau — {ex}",
                "message": f"Même poids depuis 4 séances. Essaie un schéma différent ou une surcharge progressive."
            })
            break

    # 3. PR PROCHE — current dans les 5% du PR historique
    if not any(i["type"] == "stagnation" for i in insights):
        for ex, data in weights.items():
            hist = [e for e in (data.get("history") or []) if e.get("weight")]
            if len(hist) < 3: continue
            pr      = max(e["weight"] for e in hist)
            current = data.get("current_weight") or hist[0].get("weight", 0)
            if 0 < current < pr and current >= pr * 0.95:
                gap = round(pr - current, 1)
                insights.append({
                    "type": "pr_near", "level": "success",
                    "icon": "trophy.fill", "title": f"PR en vue — {ex}",
                    "message": f"Tu es à {gap} lbs de ton record ({pr:.0f} lbs). Pousse fort !"
                })
                break

    # 4. RÉGULARITÉ — 5+ séances sur 7 jours (si pas de fatigue)
    sessions_7d = sum(1 for d in sessions if d >= dstr(now - timedelta(days=7)))
    if sessions_7d >= 5 and not any(i["type"] == "fatigue" for i in insights):
        insights.append({
            "type": "consistency", "level": "success",
            "icon": "checkmark.seal.fill", "title": "Excellente régularité",
            "message": f"{sessions_7d} séances sur les 7 derniers jours. Continue !"
        })

    # 5. MILESTONE STREAK — à 1 séance du prochain palier
    streak = 0
    for i in range(365):
        d = dstr(now - timedelta(days=i))
        if d in sessions: streak += 1
        elif i > 0: break
    for m in [7, 14, 21, 30, 50, 75, 100]:
        if streak == m - 1:
            insights.append({
                "type": "milestone", "level": "success",
                "icon": "star.fill", "title": f"Demain : streak de {m} jours !",
                "message": f"Plus qu'une séance pour atteindre {m} jours consécutifs."
            })
            break

    return jsonify({"insights": insights[:3]})


@analytics_coach_bp.route("/api/proactive_alerts")
def api_proactive_alerts():
    from alerts import get_all_alerts
    return jsonify({"alerts": get_all_alerts()})


@analytics_coach_bp.route("/api/insights/correlations")
def api_insights_correlations():
    try:
        days = int(request.args.get("days", 60))
    except ValueError:
        days = 60
    from correlations import get_correlations
    return jsonify(get_correlations(days))


@analytics_coach_bp.route("/api/smart_day")
def api_smart_day():
    """
    Returns a session recommendation for today based on:
    - Recovery score (from today's recovery log)
    - HRV trend
    - Days since last session of each type
    - ACWR load ratio
    """
    from health_data import get_daily_health_summary
    from acwr import calc_acwr
    import db as _db
    from datetime import date as date_cls, timedelta

    today = date_cls.fromisoformat(_today_mtl()).isoformat()
    summary      = get_daily_health_summary(today)
    recovery     = summary.get("recovery_score")      # 0–100
    hrv          = summary.get("hrv")
    resting_hr   = summary.get("resting_heart_rate")

    sessions_raw = _db.get_workout_sessions(limit=30)
    sessions_by_type: dict[str, int] = {}  # session_type → days since last
    for s in sessions_raw:
        stype = s.get("session_type") or "morning"
        sname = s.get("session_name") or stype
        d = s.get("date")
        if not d:
            continue
        try:
            delta = (date_cls.fromisoformat(_today_mtl()) - date_cls.fromisoformat(str(d))).days
        except ValueError:
            continue
        if sname not in sessions_by_type or delta < sessions_by_type[sname]:
            sessions_by_type[sname] = delta

    days_rest = min(sessions_by_type.values(), default=7)

    try:
        acwr_data = calc_acwr()
        acwr = acwr_data.get("acwr")
    except Exception:
        acwr = None

    if recovery is not None:
        score = recovery  # 0–100
    else:
        score = 50.0

    if hrv is not None:
        if hrv >= 60:   score = min(100, score + 10)
        elif hrv < 30:  score = max(0,   score - 15)

    if acwr is not None and acwr > 1.5:
        score = max(0, score - 20)

    if score >= 70:
        intensity  = "normale"
        confidence = round(min(0.95, 0.70 + score / 1000), 2)
        if days_rest == 0:
            reason = "Récupération optimale — séance normale recommandée."
        else:
            reason = f"Récupération optimale ({int(score)}/100) — c'est le moment de pousser."
        cta = "💪 Entraîne-toi"
    elif score >= 50:
        intensity  = "réduite"
        confidence = round(min(0.85, 0.55 + score / 1000), 2)
        reason = f"Récupération modérée ({int(score)}/100) — privilégie un volume réduit ou technique."
        cta = "🟡 Volume réduit"
    elif days_rest >= 3:
        intensity  = "normale"
        confidence = 0.60
        reason = f"Récupération faible ({int(score)}/100) mais {days_rest} jours sans séance — écoute ton corps."
        cta = "⚠️ Léger ou repos"
    else:
        intensity  = "repos"
        confidence = round(min(0.90, 0.65 + (100 - score) / 200), 2)
        reason = f"Récupération insuffisante ({int(score)}/100) — repos actif ou mobilité."
        cta = "😴 Repos recommandé"

    suggested_session: str | None = None
    if intensity != "repos" and sessions_by_type:
        suggested_session = max(sessions_by_type, key=lambda k: sessions_by_type[k])

    return jsonify({
        "intensity":          intensity,
        "confidence":         confidence,
        "reason":             reason,
        "cta":                cta,
        "recovery_score":     recovery,
        "hrv":                hrv,
        "resting_hr":         resting_hr,
        "acwr":               acwr,
        "days_since_session": days_rest,
        "suggested_session":  suggested_session,
    })


@analytics_coach_bp.route("/api/weekly_report")
def api_weekly_report():
    """Aggregated summary for the last 7 days: volume, PRs, recovery, nutrition, sleep."""
    from health_data import get_weekly_health_summary
    from weights import load_weights
    from nutrition import get_recent_days
    import db as _db
    from datetime import date as date_cls, timedelta

    today = date_cls.fromisoformat(_today_mtl())
    week_start = (today - timedelta(days=6)).isoformat()

    sessions_raw = _db.get_workout_sessions(limit=30)
    week_sessions = [
        s for s in sessions_raw
        if s.get("date") and str(s["date"]) >= week_start
        and (s.get("completed") or s.get("rpe") is not None)
    ]
    hiit_week = [
        h for h in (_db.get_hiit_logs(limit=30) or [])
        if h.get("date") and str(h["date"]) >= week_start
    ]
    session_count = len(week_sessions) + len(hiit_week)

    def _total_reps(reps_str: str) -> int:
        total = 0
        for p in str(reps_str).split(","):
            p = p.strip()
            if p.isdigit():
                total += int(p)
            elif "-" in p:
                bounds = p.split("-")
                if len(bounds) == 2 and bounds[0].strip().isdigit() and bounds[1].strip().isdigit():
                    total += (int(bounds[0].strip()) + int(bounds[1].strip())) // 2
        return total

    def _avg_reps(reps_str: str) -> float:
        parts = [int(p.strip()) for p in str(reps_str).split(",") if p.strip().isdigit()]
        return sum(parts) / len(parts) if parts else 1.0

    weights   = load_weights()
    total_vol = 0.0
    pr_count  = 0
    prs_list: list[str] = []
    top_exercise: str | None = None
    top_vol = 0.0
    for name, data in weights.items():
        hist = data.get("history") or []
        week_logs = [e for e in hist if e.get("date") and str(e["date"]) >= week_start]
        if not week_logs:
            continue
        ex_vol = sum(
            (e.get("weight") or 0) * _total_reps(e.get("reps") or "")
            for e in week_logs
        )
        total_vol += ex_vol
        if ex_vol > top_vol:
            top_vol = ex_vol
            top_exercise = name
        week_ones = [
            e["weight"] * (1 + _avg_reps(e.get("reps") or "1") / 30)
            for e in week_logs if e.get("weight")
        ]
        all_ones = [
            e["weight"] * (1 + _avg_reps(e.get("reps") or "1") / 30)
            for e in hist if e.get("weight") and str(e.get("date", "")) < week_start
        ]
        if week_ones and (not all_ones or max(week_ones) > max(all_ones)):
            pr_count += 1
            prs_list.append(name)

    rpe_vals = [s["rpe"] for s in week_sessions if s.get("rpe") is not None]
    avg_rpe = round(sum(rpe_vals) / len(rpe_vals), 1) if rpe_vals else None

    health_week = get_weekly_health_summary(days=7)
    sleep_vals   = [d["sleep_duration"]    for d in health_week if d.get("sleep_duration")]
    recovery_vals= [d["recovery_score"]    for d in health_week if d.get("recovery_score")]
    steps_vals   = [d["steps"]             for d in health_week if d.get("steps")]
    hrv_vals     = [d["hrv"]               for d in health_week if d.get("hrv")]

    avg_sleep    = round(sum(sleep_vals)    / len(sleep_vals),    1) if sleep_vals    else None
    avg_recovery = round(sum(recovery_vals) / len(recovery_vals), 1) if recovery_vals else None
    avg_steps    = int(sum(steps_vals)      / len(steps_vals))        if steps_vals    else None
    avg_hrv      = round(sum(hrv_vals)      / len(hrv_vals),      1) if hrv_vals      else None

    nutr_days = get_recent_days(7)
    from nutrition import load_settings as load_nutrition_settings
    nutr_settings = load_nutrition_settings() or {}
    cal_target = nutr_settings.get("calorie_limit") or 0
    if cal_target > 0 and nutr_days:
        compliant = sum(
            1 for d in nutr_days
            if d.get("calories") and abs(d["calories"] - cal_target) / cal_target <= 0.10
        )
        nutrition_compliance = round(compliant / len(nutr_days) * 100)
    else:
        nutrition_compliance = None

    pts = min(int(session_count / 5 * 30), 30)
    if avg_sleep is not None:
        pts += 25 if avg_sleep >= 7.5 else 20 if avg_sleep >= 7 else 15 if avg_sleep >= 6.5 else 8
    else:
        pts += 12
    if nutrition_compliance is not None:
        pts += 25 if nutrition_compliance >= 80 else 18 if nutrition_compliance >= 60 else 12 if nutrition_compliance >= 40 else 6
    else:
        pts += 12
    if avg_recovery is not None:
        pts += 20 if avg_recovery >= 7 else 15 if avg_recovery >= 5 else 10 if avg_recovery >= 3 else 5
    else:
        pts += 10
    weekly_score = min(pts, 100)

    focus: list[str] = []
    if avg_sleep is not None and avg_sleep < 7:
        focus.append(f"Améliore ton sommeil (moy. {avg_sleep}h) — vise 7h+")
    if nutrition_compliance is not None and nutrition_compliance < 70:
        focus.append(f"Compliance nutrition à {nutrition_compliance}% — vise 80%+")
    if session_count < 3:
        focus.append("Vise au moins 3 séances cette semaine")
    if avg_rpe is not None and avg_rpe > 8.5:
        focus.append("RPE élevé — inclure une journée de récupération active")
    if pr_count > 0:
        focus.append(f"{pr_count} PR cette semaine — consolide avant d'augmenter les charges")
    if not focus:
        focus.append("Continue sur ta lancée — belle semaine !")

    return jsonify({
        "week_start":            week_start,
        "week_end":              today.isoformat(),
        "session_count":         session_count,
        "total_volume_lbs":      round(total_vol),
        "pr_count":              pr_count,
        "top_exercise":          top_exercise,
        "avg_recovery_score":    avg_recovery,
        "avg_sleep_hours":       avg_sleep,
        "avg_steps":             avg_steps,
        "avg_hrv":               avg_hrv,
        "nutrition_compliance":  nutrition_compliance,
        "avg_rpe":               avg_rpe,
        "weekly_score":          weekly_score,
        "prs":                   prs_list,
        "focus_next_week":       focus,
        "push_pull_ratio":       _compute_push_pull_ratio(week_start),
    })


def _compute_push_pull_ratio(since_date: str) -> dict:
    """Compute push vs pull volume ratio using inventory pattern tags (28 days)."""
    import db as _db
    try:
        pv = _db.get_pattern_volume(28)
        push_vol = float(pv.get("push",  0))
        pull_vol = float(pv.get("pull",  0))
        legs_vol = float(pv.get("squat", 0)) + float(pv.get("hinge", 0))

        ratio = round(push_vol / pull_vol, 2) if pull_vol > 0 else None
        imbalance = None
        if ratio is not None:
            if ratio > 1.3:
                imbalance = "push_dominant"
            elif ratio < 0.77:
                imbalance = "pull_dominant"
        return {
            "push_volume": round(push_vol),
            "pull_volume": round(pull_vol),
            "legs_volume": round(legs_vol),
            "ratio":       ratio,
            "imbalance":   imbalance,
        }
    except Exception:
        return {}


def _total_reps_str(reps: str) -> float:
    parts = [p.strip() for p in str(reps).split(",") if p.strip().isdigit()]
    if parts:
        return sum(int(p) for p in parts)
    try:
        return float(reps)
    except Exception:
        return 1.0


@analytics_coach_bp.route("/api/selfcare_pss_analysis")
def api_selfcare_pss_analysis():
    """Analyse la relation entre les streaks self-care et les scores PSS."""
    import db as _db
    from datetime import date as date_cls, timedelta

    streaks  = _db.get_self_care_streaks_computed()
    pss_recs = _db.get_pss_records(limit=20)
    sc_log   = _db.get_self_care_log(days=90)

    if not pss_recs:
        return jsonify({"correlation": None, "message": "Aucun enregistrement PSS"})

    pss_with_sc = []
    for rec in pss_recs:
        d = str(rec.get("date") or rec.get("created_at") or "")[:10]
        if not d:
            continue
        pss_score = rec.get("pss_score") or rec.get("score")
        if pss_score is None:
            continue
        total_sc = 0
        for i in range(1, 8):
            prev = (date_cls.fromisoformat(d) - timedelta(days=i)).isoformat()
            total_sc += len(sc_log.get(prev, []))
        pss_with_sc.append({"date": d, "pss": float(pss_score), "sc_completions": total_sc})

    if len(pss_with_sc) < 3:
        return jsonify({"data": pss_with_sc, "correlation": None, "message": "Données insuffisantes"})

    xs = [p["sc_completions"] for p in pss_with_sc]
    ys = [p["pss"] for p in pss_with_sc]
    n  = len(xs)
    mx = sum(xs) / n
    my = sum(ys) / n
    num   = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    den_x = sum((x - mx) ** 2 for x in xs) ** 0.5
    den_y = sum((y - my) ** 2 for y in ys) ** 0.5
    r = round(num / (den_x * den_y), 3) if den_x > 0 and den_y > 0 else None

    message = None
    if r is not None:
        if r < -0.35:
            message = f"Self-care réduit le stress PSS (r={r:+.2f}). Plus tu pratiques, moins tu stresses."
        elif r > 0.35:
            message = f"Corrélation positive inattendue (r={r:+.2f}). Le stress te motive peut-être à prendre soin de toi."
        else:
            message = f"Pas de corrélation significative (r={r:+.2f}, n={n}). Continue à analyser avec plus de données."

    return jsonify({
        "data":        pss_with_sc,
        "correlation": r,
        "n":           n,
        "message":     message,
        "streaks":     streaks[:5],
    })


@analytics_coach_bp.route("/api/adherence")
def api_adherence():
    """Adherence % per pillar (Body/Mind/Fuel/Spirit) for the current calendar month."""
    import db as _db
    from datetime import date

    today        = date.fromisoformat(_today_mtl())
    month_prefix = today.strftime("%Y-%m")
    first_day    = today.replace(day=1)
    days_elapsed = (today - first_day).days + 1

    def _pct(active: int) -> int:
        return round(active / days_elapsed * 100) if days_elapsed > 0 else 0

    body_days   = _db.get_adherence_active_days("body",   month_prefix)
    mind_days   = _db.get_adherence_active_days("mind",   month_prefix)
    fuel_days   = _db.get_adherence_active_days("fuel",   month_prefix)
    spirit_days = _db.get_adherence_active_days("spirit", month_prefix)

    return jsonify({
        "body_pct":     _pct(body_days),
        "mind_pct":     _pct(mind_days),
        "fuel_pct":     _pct(fuel_days),
        "spirit_pct":   _pct(spirit_days),
        "days_elapsed": days_elapsed,
        "period":       month_prefix,
        "fuel_days":    fuel_days,
    })


@analytics_coach_bp.route("/api/energy_performance_correlation")
def api_energy_performance_correlation():
    """Pearson correlation entre énergie pré-séance et RPE."""
    import db as _db

    sessions_raw = _db.get_workout_sessions(limit=90)
    pairs = []
    for s in sessions_raw:
        energy = s.get("energy_pre")
        rpe    = s.get("rpe")
        d      = str(s.get("date") or "")[:10]
        if energy is not None and rpe is not None and d:
            try:
                pairs.append({"energy": float(energy), "rpe": float(rpe), "date": d})
            except (TypeError, ValueError):
                pass

    n = len(pairs)
    if n < 10:
        return jsonify({
            "correlation":      None,
            "n":                n,
            "insufficient_data": True,
            "message":          f"Minimum 10 séances avec énergie + RPE requis ({n} disponibles).",
        })

    xs = [p["energy"] for p in pairs]
    ys = [p["rpe"]    for p in pairs]
    mx = sum(xs) / n
    my = sum(ys) / n
    num   = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    den_x = sum((x - mx) ** 2 for x in xs) ** 0.5
    den_y = sum((y - my) ** 2 for y in ys) ** 0.5
    r = round(num / (den_x * den_y), 3) if den_x > 0 and den_y > 0 else None

    low_energy_rpes  = [p["rpe"] for p in pairs if p["energy"] <= 4]
    high_energy_rpes = [p["rpe"] for p in pairs if p["energy"] >= 7]
    avg_rpe_low  = round(sum(low_energy_rpes)  / len(low_energy_rpes),  1) if low_energy_rpes  else None
    avg_rpe_high = round(sum(high_energy_rpes) / len(high_energy_rpes), 1) if high_energy_rpes else None

    if r is not None and r < -0.35:
        insight = (
            f"L'énergie pré-séance prédit ton RPE (r={r:+.2f}). "
            f"Quand tu te sens à plat, ton effort perçu grimpe."
            + (f" RPE moyen : {avg_rpe_low}/10 (énergie basse) vs {avg_rpe_high}/10 (énergie haute)."
               if avg_rpe_low and avg_rpe_high else "")
        )
    elif r is not None and abs(r) < 0.20:
        insight = (
            f"Pas de corrélation significative entre énergie et RPE (r={r:+.2f}, n={n}). "
            "Tu performes de façon constante quelle que soit ton énergie de départ."
        )
    elif r is not None:
        insight = (
            f"Corrélation modérée entre énergie et effort perçu (r={r:+.2f}). "
            "Continue à tracker pour affiner le pattern."
        )
    else:
        insight = "Données insuffisantes pour calculer la corrélation."

    return jsonify({
        "correlation":       r,
        "n":                 n,
        "pairs":             pairs[-30:],
        "avg_rpe_low_energy":  avg_rpe_low,
        "avg_rpe_high_energy": avg_rpe_high,
        "insight":           insight,
    })
