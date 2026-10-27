from flask import Blueprint, jsonify, request
from collections import defaultdict
from datetime import datetime, timedelta, date as _date
from dataclasses import fields, is_dataclass
from enum import Enum
import math
import re
import logging
import time
from utils import _today_mtl

logger = logging.getLogger("trainingos")

from cockpit_analytics_service import CockpitAnalyticsConfig, build_cockpit_analytics
from metric_semantics import DateWindow

analytics_stats_bp = Blueprint("analytics_stats", __name__)


def _serialize_cockpit(value):
    """Convert typed cockpit DTOs to JSON-safe values without formatting facts."""
    if isinstance(value, Enum):
        return _serialize_cockpit(value.value)
    if type(value) is _date:
        return value.isoformat()
    if is_dataclass(value):
        return {field.name: _serialize_cockpit(getattr(value, field.name)) for field in fields(value)}
    if isinstance(value, tuple) or isinstance(value, list):
        return [_serialize_cockpit(item) for item in value]
    if isinstance(value, dict):
        if any(not isinstance(key, str) for key in value):
            raise TypeError("cockpit dictionaries require string keys")
        return {key: _serialize_cockpit(item) for key, item in value.items()}
    if isinstance(value, float):
        if not math.isfinite(value):
            raise ValueError("non-finite cockpit float")
        return value
    if value is None or isinstance(value, (str, int, bool)):
        return value
    raise TypeError(f"unsupported cockpit value: {type(value).__name__}")


def _strict_query_date(name: str) -> _date:
    value = request.args.get(name)
    if value is None or re.fullmatch(r"\d{4}-\d{2}-\d{2}", value) is None:
        raise ValueError(f"{name} must be YYYY-MM-DD")
    try:
        return _date.fromisoformat(value)
    except ValueError as exc:
        raise ValueError(f"{name} must be YYYY-MM-DD") from exc


def _strict_query_days(name: str) -> int:
    value = request.args.get(name)
    if value is None or re.fullmatch(r"[0-9]+", value) is None:
        raise ValueError(f"{name} must be a positive integer")
    parsed = int(value)
    if parsed <= 0:
        raise ValueError(f"{name} must be a positive integer")
    return parsed


def _aggregate_sessions_by_date(rows: list[dict], hiit_rows: list[dict] | None = None) -> dict[str, dict]:
    """Regroupe 1..N workout_sessions par date en UNE entry agrégée.

    Filtre d'entrée workout : (completed OR rpe not None).
    Tri intra-groupe : logged_at ASC (matin → soir).

    Règles par champ (cf. audit Stats Lot B) :
      rpe          : moyenne des non-nil arrondie 0.1
      duration_min : somme des non-nil
      energy_pre   : première non-nil (matin — signal état de fatigue au réveil)
      comment      : première non-vide (matin)
      logged_at    : max
      completed    : any
      session_count: workout slots (len(entries)) + HIIT slots du jour.
                     Partagé par /api/dashboard qui ajoute HIIT en passe finale →
                     invariant d'égalité tient sur les mêmes dates.

    NE PAS produire session_volume : le volume Stats vient de weights.history
    (exercise_logs), l'ajouter ici doublerait le comptage.
    """
    groups: dict[str, list[dict]] = defaultdict(list)
    for s in rows:
        if not isinstance(s, dict):
            continue
        if not (s.get("completed") or s.get("rpe") is not None):
            continue
        d = s.get("date")
        if d:
            groups[d].append(s)

    hiit_count_by_date: dict[str, int] = {}
    for h in hiit_rows or ():
        if not isinstance(h, dict):
            continue
        d = h.get("date")
        if d:
            hiit_count_by_date[d] = hiit_count_by_date.get(d, 0) + 1

    out: dict[str, dict] = {}
    for date, entries in groups.items():
        entries.sort(key=lambda e: e.get("logged_at") or "")

        rpes      = [float(e["rpe"])          for e in entries if e.get("rpe")          is not None]
        durations = [float(e["duration_min"]) for e in entries if e.get("duration_min") is not None]
        energies  = [int(e["energy_pre"])     for e in entries if e.get("energy_pre")   is not None]
        comments  = [str(e["comment"])        for e in entries if e.get("comment")]

        out[date] = {
            "date":          date,
            "rpe":           round(sum(rpes) / len(rpes), 1) if rpes else None,
            "duration_min":  sum(durations)                    if durations else None,
            "energy_pre":    energies[0]                       if energies else None,
            "comment":       comments[0]                       if comments else None,
            "logged_at":     max((e.get("logged_at") or "") for e in entries) or None,
            "completed":     any(bool(e.get("completed")) for e in entries),
            "session_count": len(entries) + hiit_count_by_date.get(date, 0),
        }
    return out


@analytics_stats_bp.route("/api/stats_data")
def api_stats_data():
    """LEGACY / DEPRECATED aggregate kept temporarily for existing consumers.

    Do not extend this payload for new features. Prefer targeted endpoints, or
    /api/stats/cockpit for modern Stats domains; the cockpit is not a complete
    replacement for this compatibility endpoint.
    """
    from weights import load_weights
    from body_weight import load_body_weight
    from nutrition import (load_settings as load_nutrition_settings)
    from inventory import load_inventory
    from utils import (_calc_muscle_stats, _calc_weekly_sets_per_muscle,
                        _calc_weekly_indirect_per_muscle, _calc_weekly_specific_breakdown,
                        MUSCLE_LANDMARKS)
    import db as _db
    from utils import load_hiit_log

    weights      = load_weights()
    _cutoff_180  = (_date.fromisoformat(_today_mtl()) - timedelta(days=180)).isoformat()
    all_sessions = _db.get_workout_sessions(limit=500, since=_cutoff_180)
    hiit_log     = load_hiit_log()
    sessions     = _aggregate_sessions_by_date(all_sessions, hiit_log)
    body_weight  = load_body_weight()
    recovery_log = _db.get_recovery_logs() or []
    nutr_settings = load_nutrition_settings()
    nutr_entries  = _db.get_nutrition_daily_full(180)
    inventory       = load_inventory() or {}
    muscle_stats     = _calc_muscle_stats(sessions, weights, inventory)
    weekly_sets      = _calc_weekly_sets_per_muscle(weights, inventory)
    weekly_specific  = _calc_weekly_specific_breakdown(weights, inventory)
    weekly_indirect  = _calc_weekly_indirect_per_muscle(weights, inventory)
    # Direct = _calc_weekly_specific_breakdown (mg primaire mappé). Indirect = comptage direct
    # (fonction dédiée), PAS soustraction total−direct — cette dernière casse dès qu'un exo a
    # son muscle primaire aussi listé dans muscles[] (double-compte). Cf. dossier landmarks 2026-09.
    direct_totals    = {k: sum(v.values()) for k, v in weekly_specific.items()}
    inventory_types  = {name: info.get("type") or "machine" for name, info in inventory.items()}

    tracked_muscles = set(muscle_stats.keys()) | set(weekly_sets.keys())
    muscle_landmarks = {
        muscle: {
            **MUSCLE_LANDMARKS[muscle],
            "weekly_sets_direct":   direct_totals.get(muscle, 0),
            "weekly_sets_indirect": weekly_indirect.get(muscle, 0),
            "specific_detail":      weekly_specific.get(muscle) or None,
        }
        for muscle in tracked_muscles
        if muscle in MUSCLE_LANDMARKS
    }

    from utils import get_current_week
    # Pre-filter nutr_entries (already fetched, 180 days) to the 60-day window
    # shared by get_macros_by_day_type and get_protein_weight_ratio — avoids 2 extra DB reads.
    _cutoff_60   = (_date.fromisoformat(_today_mtl()) - timedelta(days=60)).isoformat()
    _nutr_60     = [d for d in nutr_entries if (d.get("date") or "") >= _cutoff_60]

    weekly_tonnage       = _db.get_weekly_tonnage(26)
    pattern_volume       = _db.get_pattern_volume(28, weights=weights, inventory=inventory)
    programme_compliance = _db.get_programme_compliance(8)
    one_rm_trend         = _db.get_one_rm_trend(84, weights=weights, inventory=inventory)
    macros_by_day_type   = _db.get_macros_by_day_type(60, nutr_days=_nutr_60)
    protein_weight_ratio = _db.get_protein_weight_ratio(60, nutr_days=_nutr_60)

    return jsonify({
        "weights":               weights,
        "sessions":              sessions,
        "hiit_log":              hiit_log,
        "body_weight":           body_weight,
        "recovery_log":          recovery_log,
        "nutrition_target":      nutr_settings,
        "nutrition_days":        nutr_entries,
        "week":                  get_current_week(),
        "muscle_stats":          muscle_stats,
        "inventory_types":       inventory_types,
        "muscle_landmarks":      muscle_landmarks,
        "weekly_tonnage":        weekly_tonnage,
        "pattern_volume":        pattern_volume,
        "programme_compliance":  programme_compliance,
        "one_rm_trend":          one_rm_trend,
        "macros_by_day_type":    macros_by_day_type,
        "protein_weight_ratio":  protein_weight_ratio,
    })


@analytics_stats_bp.route("/api/stats/cockpit", methods=["GET"])
def api_stats_cockpit():
    """Return the typed Stats cockpit contract for explicit requested windows."""
    from datetime import timedelta
    import db as _db

    try:
        as_of = _strict_query_date("as_of")
        progression_days = _strict_query_days("progression_days")
        weekly_days = _strict_query_days("weekly_days")
        muscle_days = _strict_query_days("muscle_days")
        muscle_period = DateWindow(as_of - timedelta(days=muscle_days - 1), as_of)
        # Fenêtre précédente de même longueur, collée à muscle_period :
        # [start − N, start − 1]. Permet le visuel "courant vs précédent"
        # dans "Détail musculaire" sans paramètre additionnel iOS.
        muscle_previous_period = DateWindow(
            muscle_period.start - timedelta(days=muscle_days),
            muscle_period.start - timedelta(days=1),
        )
        config = CockpitAnalyticsConfig(
            as_of=as_of,
            progression_days=progression_days,
            weekly_period=DateWindow(as_of - timedelta(days=weekly_days - 1), as_of),
            muscle_period=muscle_period,
            muscle_previous_period=muscle_previous_period,
        )
    except (TypeError, ValueError) as exc:
        return jsonify({"error": str(exc)}), 400

    # Décharges volontaires : source unique deload_periods via is_deload_day
    # (migration 080). cycle_start_date reste réservé à la prescription programme
    # (/api/mesocycle_status, utils.get_mesocycle_info) — ne passe plus ici.
    response = build_cockpit_analytics(_db._client, config)
    return jsonify(_serialize_cockpit(response))


@analytics_stats_bp.route("/api/stats/streaks")
def api_stats_streaks():
    """
    Source de vérité unique pour le streak — logique extraite dans
    weekly_streaks.compute (importée aussi par workout_dna pour aligner
    le DNA sur le même streak hebdomadaire que le dashboard).
    """
    from datetime import datetime as _dtt
    from weekly_streaks import compute as _compute_weekly_streaks

    date_param = request.args.get("date", "").strip()
    try:
        _dtt.strptime(date_param, "%Y-%m-%d")
        today_str = date_param
    except (ValueError, Exception):
        today_str = _today_mtl()

    return jsonify(_compute_weekly_streaks(today_str))


_stats_wellness_cache: dict = {}

@analytics_stats_bp.route("/api/stats_wellness")
def api_stats_wellness():
    """Wellness correlations and mental health data for the Stats Bien-être tab."""
    import db as _db
    _now = time.time()
    if _stats_wellness_cache.get("ts", 0) + 1800 > _now:
        return jsonify(_stats_wellness_cache["data"])
    data = {
        "mood_trend":              _db.get_mood_trend(60),
        "pss_history":             _db.get_pss_records(limit=20),
        "self_care_streaks":       _db.get_self_care_streaks_computed(),
        "self_care_compliance":    _db.get_self_care_compliance(30),
        "soreness_volume_scatter": _db.get_soreness_volume_scatter(),
        "sleep_volume_scatter":    _db.get_sleep_volume_scatter(),
        "rpe_progression":         _db.get_rpe_progression(),
        "rir_by_exercise":         _db.get_rir_by_exercise(),
    }
    _stats_wellness_cache.update({"ts": _now, "data": data})
    return jsonify(data)


@analytics_stats_bp.route("/api/nutrition_timing")
def api_nutrition_timing():
    """Analyse pre/post workout nutrition timing from nutrition_entries.heure and workout_sessions."""
    import db as _db
    from datetime import date as date_cls, timedelta

    cutoff = (date_cls.fromisoformat(_today_mtl()) - timedelta(days=60)).isoformat()
    sessions_raw = _db.get_workout_sessions(limit=60)
    session_dates = {str(s.get("date", ""))[:10] for s in sessions_raw if s.get("date")}

    pre_meals:  list[dict] = []
    post_meals: list[dict] = []
    all_macros_pre:  dict = {"calories": [], "proteines": [], "glucides": []}
    all_macros_post: dict = {"calories": [], "proteines": [], "glucides": []}

    if _db._client:
        try:
            resp = (
                _db._client.table("nutrition_entries")
                .select("date, heure, calories, proteines, glucides, lipides, aliment")
                .gte("date", cutoff)
                .not_.is_("heure", "null")
                .execute()
            )
            for row in (resp.data or []):
                d = str(row.get("date", ""))[:10]
                if d not in session_dates:
                    continue
                heure = row.get("heure") or ""
                try:
                    hour = int(str(heure)[:2])
                except Exception:
                    continue
                cal   = float(row.get("calories", 0)  or 0)
                prot  = float(row.get("proteines", 0) or 0)
                gluc  = float(row.get("glucides", 0)  or 0)
                entry = {"date": d, "hour": hour, "aliment": row.get("aliment"), "calories": cal, "protein": prot, "carbs": gluc}

                session_hour = None
                sess = next((s for s in sessions_raw if str(s.get("date", ""))[:10] == d), None)
                if sess and sess.get("started_at"):
                    try:
                        session_hour = int(str(sess["started_at"])[11:13])
                    except Exception:
                        pass

                is_pre = is_post = False
                if session_hour is not None:
                    is_pre  = (session_hour - 3) <= hour < session_hour
                    is_post = session_hour <= hour < (session_hour + 3)
                else:
                    is_pre  = 5 <= hour < 11
                    is_post = 11 <= hour < 20

                if is_pre:
                    pre_meals.append(entry)
                    for k, v in [("calories", cal), ("proteines", prot), ("glucides", gluc)]:
                        all_macros_pre[k].append(v)
                elif is_post:
                    post_meals.append(entry)
                    for k, v in [("calories", cal), ("proteines", prot), ("glucides", gluc)]:
                        all_macros_post[k].append(v)
        except Exception as e:
            logger.error("api_nutrition_timing error: %s", e)

    def avg(lst): return round(sum(lst) / len(lst), 1) if lst else None

    return jsonify({
        "training_days_analyzed": len(session_dates),
        "pre_workout": {
            "meal_count":       len(pre_meals),
            "avg_calories":     avg(all_macros_pre["calories"]),
            "avg_protein":      avg(all_macros_pre["proteines"]),
            "avg_carbs":        avg(all_macros_pre["glucides"]),
            "top_foods":        list({m["aliment"] for m in pre_meals if m.get("aliment")})[:5],
        },
        "post_workout": {
            "meal_count":       len(post_meals),
            "avg_calories":     avg(all_macros_post["calories"]),
            "avg_protein":      avg(all_macros_post["proteines"]),
            "avg_carbs":        avg(all_macros_post["glucides"]),
            "top_foods":        list({m["aliment"] for m in post_meals if m.get("aliment")})[:5],
        },
        "insight": (
            f"Tu consommes {round(avg(all_macros_post['proteines']) or 0)}g prot post-workout. "
            "La distribution protéique sur 24h prime sur le timing précis (Schoenfeld & Aragon 2013)."
            if all_macros_post["proteines"] else
            "Pas encore assez de données de timing pour analyser ta nutrition pré/post-workout."
        ),
    })


@analytics_stats_bp.route("/api/stats/force-vs-accessory")
def api_force_vs_accessory():
    """Timeline tonnage moyen/séance par catégorie (force vs accessory).

    Query params :
      weeks   — fenêtre en semaines (défaut 12, borné [1, 52])
      debug=1 — ajoute {sample: [...]} : 20 dernières séances avec ratio_force
                et session_name, pour vérification humaine de la classification.

    Payload : {timeline: [...], sample?: [...]}
    """
    from db_stats import get_force_vs_accessory_timeline, get_session_category_sample
    try:
        weeks = max(1, min(52, int(request.args.get("weeks", "12"))))
    except (ValueError, TypeError):
        weeks = 12
    payload = {"timeline": get_force_vs_accessory_timeline(weeks=weeks)}
    if request.args.get("debug") == "1":
        payload["sample"] = get_session_category_sample(limit=20)
    return jsonify(payload)


# ponytail: endpoint temp — backfill TUT (set_volume=0 pour exos time
# historiques). dry_run par défaut, safe. Supprimer après exécution validée.
@analytics_stats_bp.route("/api/stats/tut-backfill", methods=["POST"])
def api_tut_backfill():
    """Backfill : zéro-ise set_volume dans sets_json pour les rows exercise_logs
    dont l'exo lié a tracking_type='time'.

    Query param ?dry_run=1 (défaut, safe) → liste ce qui serait modifié.
    ?dry_run=0 → EXÉCUTE l'UPDATE (irréversible sans autre backfill).
    """
    from db_stats import backfill_tut_volumes
    dry_run = str(request.args.get("dry_run", "1")).lower() in ("1", "true", "yes")
    return jsonify(backfill_tut_volumes(dry_run=dry_run))


# ponytail: endpoint temp — diagnostic core volume gonflé (exos TIME comptés
# w×r sans regarder tracking_type). Supprimer après fix de calc_exercise_volume.
@analytics_stats_bp.route("/api/stats/pattern-volume-breakdown")
def api_pattern_volume_breakdown():
    """Décompose le volume d'un pattern par exo (top contributors).
    Params : pattern (défaut "core"), days (défaut 28).
    """
    from db_stats import get_pattern_volume_breakdown
    pattern = request.args.get("pattern", "core")
    try:
        days = max(1, min(365, int(request.args.get("days", "28"))))
    except (ValueError, TypeError):
        days = 28
    return jsonify({
        "pattern":   pattern,
        "days":      days,
        "breakdown": get_pattern_volume_breakdown(pattern, days),
    })


# ponytail: endpoint temp — supprimer après validation de la règle de classification.
@analytics_stats_bp.route("/api/stats/force-vs-accessory/simulate")
def api_force_vs_accessory_simulate():
    """Simule 2 variantes de classification par `exercises.category`.

    Payload : {fill: {...}, sample: [{..., variant_A, variant_B}]}
    variant_A : force = {push, pull, legs}         (strength+core = accessory)
    variant_B : force = {push, pull, legs, strength} (core seul = accessory)
    """
    from db_stats import simulate_category_classification
    return jsonify(simulate_category_classification(limit=20))


@analytics_stats_bp.route("/api/stats/nutrition_history")
def api_stats_nutrition_history():
    """Historique nutrition + cible calorique adaptative PAR JOUR sur la fenêtre.

    Payload par jour :
      date, calories, proteines, glucides, lipides, target_calories,
      source ("detailed"/"estimated"/null si jour vide),
      pct_calories_declared, pct_proteines_declared, target_calories_snapshot
      (null pour jours détaillés OU estimations antérieures à la migration 098).

    - Exactement `days` entrées consécutives (plus ancien → récent, aucun trou
      de date). Jours sans saisie nutrition → macros null (jamais 0 — trou de
      saisie ≠ zéro calorique).
    - target_calories calculée via une SEULE série TDEE (tdee.compute_target
      _calories_series) — moyenne glissante 7 TDEE précédents + goal adjust.
      Null si <7 jours de TDEE antérieurs à cette date.
    - Conformité consommateur :
        detailed → calories / target_calories
        estimated avec pct → pct_calories_declared (ratio direct)
        estimated SANS pct → exclu (compter et afficher "N jours sans pct")

    Query : days ∈ [1, 180], défaut 60.
    """
    import db as _db
    from tdee import compute_target_calories_series

    try:
        days = int(request.args.get("days", 60))
    except (TypeError, ValueError):
        return jsonify({"error": "days doit être un entier"}), 400
    if days < 1 or days > 180:
        return jsonify({"error": "days doit être entre 1 et 180"}), 400

    today_str = _today_mtl()
    today = _date.fromisoformat(today_str)

    # Macros loggées par date (jours vides filtrés par get_nutrition_daily_full).
    try:
        logged = _db.get_nutrition_daily_full(days=days) or []
    except Exception as e:
        logger.exception("nutrition_history: get_nutrition_daily_full: %s", e)
        return jsonify({"error": str(e)}), 500
    logged_by_date = {str(d.get("date") or "")[:10]: d for d in logged}

    # Cibles caloriques adaptatives — une seule passe TDEE.
    # Pas de fallback silencieux : une exception infra remonte en 500
    # explicite plutôt que de masquer en targets null partout.
    try:
        targets = compute_target_calories_series(days=days, end_date=today_str)
    except Exception as e:
        logger.exception("nutrition_history: compute_target_calories_series: %s", e)
        return jsonify({"error": str(e)}), 500

    result = []
    for i in range(days - 1, -1, -1):   # plus ancien → récent
        d = today - timedelta(days=i)
        d_str = d.isoformat()
        row = logged_by_date.get(d_str)
        if row is None:
            cal = prot = carbs = fat = None
            source = pct_cal = pct_prot = tgt_snapshot = None
        else:
            cal   = row.get("calories")
            prot  = row.get("proteines")
            carbs = row.get("glucides")
            fat   = row.get("lipides")
            source       = row.get("source")
            pct_cal      = row.get("pct_calories_declared")
            pct_prot     = row.get("pct_proteines_declared")
            tgt_snapshot = row.get("target_calories_snapshot")
        result.append({
            "date":                     d_str,
            "calories":                 cal,
            "proteines":                prot,
            "glucides":                 carbs,
            "lipides":                  fat,
            "target_calories":          targets.get(d_str),
            "source":                   source,
            "pct_calories_declared":    pct_cal,
            "pct_proteines_declared":   pct_prot,
            "target_calories_snapshot": tgt_snapshot,
        })
    return jsonify(result)
