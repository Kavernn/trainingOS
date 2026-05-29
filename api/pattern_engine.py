"""
pattern_engine.py — Cross-module pattern detection.

7 families:
  A  Exercise × Condition    (PSS, sommeil, soreness, HRV → volume exercice)
  B  Temporal segmentation   (jour de semaine → RPE/volume)
  C  Nutrition J-1 → exercice (protéines/glucides veille → volume exercice)
  D  Skip → Stress           (séances manquées/semaine → PSS moyen)
  E  War Room × Activité     (trigger count/intensity vs. workout presence) [war_room:True]
  F  Spirit × Mind           (breathwork/meditation → PSS/soreness)
  G  War Room reset × J+1    (reset day → volume/RPE le lendemain)   [war_room:True]

Seuil de significativité adaptatif (p < 0.05 two-tailed, approximation t_crit=2.0).
"""
from __future__ import annotations

import math
import time as _time
import logging
from collections import defaultdict
from datetime import date as date_cls, timedelta, timezone, datetime

import db
from utils import _today_mtl

logger = logging.getLogger("trainingos.pattern_engine")

# ── Stats helpers ─────────────────────────────────────────────────────────────

def _mean(v: list[float]) -> float:
    return sum(v) / len(v) if v else 0.0


def _std(v: list[float], mu: float) -> float:
    return math.sqrt(sum((x - mu) ** 2 for x in v) / (len(v) - 1)) if len(v) >= 2 else 0.0


def _cohen_d(a: list[float], b: list[float]) -> float:
    if len(a) < 2 or len(b) < 2:
        return 0.0
    ma, mb = _mean(a), _mean(b)
    sa, sb = _std(a, ma), _std(b, mb)
    na, nb = len(a), len(b)
    pooled = math.sqrt(((na - 1) * sa ** 2 + (nb - 1) * sb ** 2) / (na + nb - 2))
    return (ma - mb) / pooled if pooled > 1e-9 else 0.0


def _pearson(xs: list[float], ys: list[float]) -> float | None:
    n = len(xs)
    if n < 8:
        return None
    mx, my = _mean(xs), _mean(ys)
    num = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    dx = math.sqrt(sum((x - mx) ** 2 for x in xs))
    dy = math.sqrt(sum((y - my) ** 2 for y in ys))
    if dx < 1e-9 or dy < 1e-9:
        return None
    return round(num / (dx * dy), 4)


def _r_crit(n: int) -> float:
    """Adaptive critical r for p<0.05 two-tailed (t_crit ≈ 2.0)."""
    if n <= 3:
        return 1.0
    return 2.0 / math.sqrt(4.0 + n - 2)


def _ok_r(r: float, n: int) -> bool:
    return abs(r) >= _r_crit(n)


def _ok_d(d: float, n_min: int) -> bool:
    return abs(d) >= 0.5 and n_min >= 5


def _confidence(effect: float, n: int) -> str:
    return "forte" if abs(effect) >= 0.65 or n >= 30 else "modérée"


# ── Volume per exercise_log entry ─────────────────────────────────────────────

def _entry_volume(e: dict) -> float | None:
    sets = e.get("sets")
    if isinstance(sets, list) and sets:
        total = 0.0
        for s in sets:
            w = float(s.get("weight") or e.get("weight") or 0)
            r = s.get("reps") or "0"
            try:
                r = float(str(r).split("-")[0])
            except (ValueError, TypeError):
                r = 0.0
            total += w * r
        return total if total > 0 else None
    w = e.get("weight")
    r = e.get("reps")
    if not w or not r:
        return None
    try:
        return float(w) * float(str(r).split("-")[0])
    except (ValueError, TypeError):
        return None


# ── Data loaders ──────────────────────────────────────────────────────────────

def _load_context(days: int = 90) -> dict[str, dict]:
    today  = date_cls.fromisoformat(_today_mtl())
    window = {(today - timedelta(days=i)).isoformat() for i in range(days)}
    ctx: dict[str, dict] = {d: {} for d in window}

    # Initialise binary fields so "no session" is explicitly 0 not missing
    for d in ctx:
        ctx[d]["breathwork_done"] = 0.0
        ctx[d]["meditation_done"] = 0.0
        ctx[d]["is_reset_day"]    = 0.0

    for e in (db.get_recovery_logs(limit=days + 10) or []):
        d = str(e.get("date") or "")[:10]
        if d not in ctx:
            continue
        for k in ("sleep_hours", "sleep_quality", "hrv", "soreness", "resting_hr"):
            v = e.get(k)
            if v is not None:
                ctx[d][k] = float(v)

    for e in (db.get_pss_records(limit=days + 10) or []):
        d = str(e.get("date") or e.get("created_at") or "")[:10]
        if d not in ctx:
            continue
        s = e.get("pss_score") or e.get("score")
        if s is not None:
            ctx[d]["pss_score"] = float(s)

    for e in (db.get_mood_logs(days=days) or []):
        d = str(e.get("date") or "")[:10]
        if d not in ctx:
            continue
        score = e.get("score")
        if score is not None:
            ctx[d]["mood_score"] = float(score)

    if db._client:
        cutoff     = (today - timedelta(days=days)).isoformat()
        cutoff_ts  = cutoff + "T00:00:00"

        # Nutrition
        try:
            rows = db._client.table("nutrition_entries").select("date, proteines, glucides, calories").gte("date", cutoff).execute().data or []
            for r in rows:
                d = str(r.get("date") or "")[:10]
                if d not in ctx:
                    continue
                ctx[d]["protein"]  = round(ctx[d].get("protein",  0) + float(r.get("proteines") or 0), 1)
                ctx[d]["carbs"]    = round(ctx[d].get("carbs",    0) + float(r.get("glucides")  or 0), 1)
                ctx[d]["calories"] = round(ctx[d].get("calories", 0) + float(r.get("calories")  or 0), 1)
        except Exception as e:
            logger.exception("_load_context nutrition source failed: %s", e)

        # Spirit — breathwork
        try:
            rows = db._client.table("breathwork_sessions").select("started_at").gte("started_at", cutoff_ts).execute().data or []
            for r in rows:
                d = str(r.get("started_at") or "")[:10]
                if d in ctx:
                    ctx[d]["breathwork_done"] = 1.0
        except Exception as e:
            logger.exception("_load_context breathwork source failed: %s", e)

        # Spirit — meditation (completed only)
        try:
            rows = db._client.table("meditation_sessions").select("started_at").gte("started_at", cutoff_ts).eq("completed", True).execute().data or []
            for r in rows:
                d = str(r.get("started_at") or "")[:10]
                if d in ctx:
                    ctx[d]["meditation_done"] = 1.0
        except Exception as e:
            logger.exception("_load_context meditation source failed: %s", e)

        # War Room — reset days
        try:
            rows = db._client.table("war_room_battles").select("date, status").gte("date", cutoff).execute().data or []
            for r in rows:
                d = str(r.get("date") or "")[:10]
                if d in ctx and r.get("status") == "lost":
                    ctx[d]["is_reset_day"] = 1.0
        except Exception as e:
            logger.exception("_load_context war_room_battles source failed: %s", e)

        # War Room — trigger count + mean intensity per day
        try:
            rows = db._client.table("war_room_triggers").select("date, intensity").gte("date", cutoff).execute().data or []
            for r in rows:
                d = str(r.get("date") or "")[:10]
                if d not in ctx:
                    continue
                ctx[d]["trigger_count"] = ctx[d].get("trigger_count", 0) + 1
                intens = r.get("intensity")
                if intens is not None:
                    n = ctx[d]["trigger_count"]
                    prev = ctx[d].get("trigger_intensity", 0.0)
                    ctx[d]["trigger_intensity"] = round((prev * (n - 1) + float(intens)) / n, 2)
        except Exception as e:
            logger.exception("_load_context war_room_triggers source failed: %s", e)

    return ctx


def _load_ex_by_date(days: int = 90) -> dict[str, dict[str, float]]:
    """Return {exercise: {date: max_volume}} for last N days."""
    cutoff  = (date_cls.fromisoformat(_today_mtl()) - timedelta(days=days)).isoformat()
    ex_hist = db.get_all_exercise_history() or {}
    result: dict[str, dict[str, float]] = defaultdict(dict)
    for name, entries in ex_hist.items():
        for e in entries:
            d = str(e.get("date") or "")[:10]
            if d < cutoff:
                continue
            v = _entry_volume(e)
            if v and v > 0:
                prev = result[name].get(d)
                if prev is None or v > prev:
                    result[name][d] = v
    return dict(result)


# ── Family A: Exercise × Condition ────────────────────────────────────────────

_CONDITIONS_A = [
    # (metric, threshold, op, label_cond_met, label_cond_not, icon, color)
    ("pss_score",   15.0, "lt",  "PSS < 15",       "PSS ≥ 15",        "brain.head.profile",   "purple"),
    ("pss_score",   20.0, "lt",  "PSS < 20",       "PSS ≥ 20",        "brain.head.profile",   "purple"),
    ("sleep_hours",  7.0, "gte", "Sommeil ≥ 7h",   "Sommeil < 7h",    "moon.zzz.fill",        "blue"),
    ("soreness",     3.0, "lt",  "Courbatures < 3","Courbatures ≥ 3", "bolt.heart.fill",       "orange"),
    ("hrv",         50.0, "gte", "HRV ≥ 50",       "HRV < 50",        "waveform.path.ecg",    "green"),
]

_METRIC_CAT = {
    "pss_score":   "Stress",
    "sleep_hours": "Sommeil",
    "soreness":    "Récupération",
    "hrv":         "HRV",
}


def _metric_phrase(metric: str, threshold: float, op: str) -> str:
    if metric == "pss_score":
        cmp = "sous" if op == "lt" else "au-dessus de"
        return f"ton PSS est {cmp} {int(threshold)}"
    if metric == "sleep_hours":
        return f"tu dors {'≥' if op == 'gte' else '<'} {threshold}h"
    if metric == "soreness":
        return f"tes courbatures sont {'faibles' if op == 'lt' else 'élevées'} (< {threshold}/5)"
    if metric == "hrv":
        return f"ton HRV est {'élevé' if op == 'gte' else 'bas'} ({'≥' if op == 'gte' else '<'} {int(threshold)} ms)"
    return f"{metric} {op} {threshold}"


def _scan_family_A(ex_by_date: dict, context: dict) -> list[dict]:
    patterns = []
    seen: set[str] = set()

    for exercise, date_vol in ex_by_date.items():
        if len(date_vol) < 10:
            continue

        for metric, threshold, op, lbl_met, lbl_not, icon, color in _CONDITIONS_A:
            dedup = f"{exercise}__{metric}"
            if dedup in seen:
                continue

            met_vols, not_vols = [], []
            for d, vol in date_vol.items():
                v = context.get(d, {}).get(metric)
                if v is None:
                    continue
                if (op == "lt" and v < threshold) or (op == "gte" and v >= threshold):
                    met_vols.append(vol)
                else:
                    not_vols.append(vol)

            if len(met_vols) < 5 or len(not_vols) < 5:
                continue

            d_val = _cohen_d(met_vols, not_vols)
            if not _ok_d(d_val, min(len(met_vols), len(not_vols))):
                continue

            avg_met = _mean(met_vols)
            avg_not = _mean(not_vols)
            if avg_not < 1e-6:
                continue
            pct = (avg_met - avg_not) / avg_not * 100
            if abs(pct) < 5:
                continue

            seen.add(dedup)
            direction = "mieux" if pct > 0 else "moins bien"
            ex_title  = exercise.title()
            n_total   = len(met_vols) + len(not_vols)
            headline  = (
                f"Tu performes {abs(int(pct))}% {direction} au {ex_title} "
                f"les jours où {_metric_phrase(metric, threshold, op)}"
            )
            max_avg = max(avg_met, avg_not)
            patterns.append({
                "id":         f"A__{exercise}__{metric}",
                "family":     "A",
                "sub_label":  f"Perf × {_METRIC_CAT.get(metric, metric)}",
                "headline":   headline,
                "confidence": _confidence(d_val, min(len(met_vols), len(not_vols))),
                "effect_pct": round(abs(pct), 1),
                "n":          n_total,
                "metric_d":   round(d_val, 3),
                "bar_a":      {"label": lbl_met, "value": round(avg_met, 1), "frac": round(avg_met / max_avg, 3)},
                "bar_b":      {"label": lbl_not, "value": round(avg_not, 1), "frac": round(avg_not / max_avg, 3)},
                "icon":       icon,
                "color":      color,
            })

    return patterns


# ── Family B: Temporal ─────────────────────────────────────────────────────────

_WEEKDAY_FR = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]


def _scan_family_B(sessions: list[dict]) -> list[dict]:
    by_wd_rpe: dict[int, list[float]] = defaultdict(list)
    by_wd_vol: dict[int, list[float]] = defaultdict(list)
    by_wd_dur: dict[int, list[float]] = defaultdict(list)

    for s in sessions:
        d = str(s.get("date") or "")[:10]
        if not d:
            continue
        try:
            wd = date_cls.fromisoformat(d).weekday()
        except ValueError:
            continue
        rpe = s.get("rpe")
        vol = s.get("session_volume")
        dur = s.get("duration_min")
        if rpe is not None: by_wd_rpe[wd].append(float(rpe))
        if vol is not None: by_wd_vol[wd].append(float(vol))
        if dur is not None: by_wd_dur[wd].append(float(dur))

    patterns = []
    seen: set[str] = set()

    def _compare(metric_name: str, by_wd: dict[int, list[float]], icon: str, color: str):
        active = [wd for wd, vals in by_wd.items() if len(vals) >= 5]
        for i in range(len(active)):
            for j in range(i + 1, len(active)):
                wd1, wd2 = active[i], active[j]
                v1, v2   = by_wd[wd1], by_wd[wd2]
                d_val    = _cohen_d(v1, v2)
                if not _ok_d(d_val, min(len(v1), len(v2))):
                    continue
                avg1, avg2 = _mean(v1), _mean(v2)
                ref = min(avg1, avg2)
                if ref < 1e-6:
                    continue
                pct = abs(avg1 - avg2) / ref * 100
                if pct < 12:
                    continue
                key = f"B__{metric_name}__{min(wd1, wd2)}_{max(wd1, wd2)}"
                if key in seen:
                    continue
                seen.add(key)
                hi_wd = wd1 if avg1 >= avg2 else wd2
                lo_wd = wd2 if avg1 >= avg2 else wd1
                hi_v  = max(avg1, avg2)
                lo_v  = min(avg1, avg2)
                n     = len(v1) + len(v2)
                patterns.append({
                    "id":         key,
                    "family":     "B",
                    "sub_label":  "Temporel",
                    "headline":   f"Tes séances du {_WEEKDAY_FR[hi_wd]} ont un {metric_name} {int(pct)}% plus élevé qu'au {_WEEKDAY_FR[lo_wd]}",
                    "confidence": _confidence(d_val, min(len(v1), len(v2))),
                    "effect_pct": round(pct, 1),
                    "n":          n,
                    "metric_d":   round(d_val, 3),
                    "bar_a":      {"label": _WEEKDAY_FR[hi_wd], "value": round(hi_v, 1), "frac": 1.0},
                    "bar_b":      {"label": _WEEKDAY_FR[lo_wd], "value": round(lo_v, 1), "frac": round(lo_v / hi_v, 3)},
                    "icon":       icon,
                    "color":      color,
                })

    _compare("RPE",    by_wd_rpe, "chart.bar.fill",   "orange")
    _compare("volume", by_wd_vol, "dumbbell.fill",     "teal")
    _compare("durée",  by_wd_dur, "clock.fill",        "blue")
    return patterns


# ── Family C: Nutrition J-1 → exercice ───────────────────────────────────────

_NUTR_META = [
    ("protein",  "protéines", "fork.knife",  "purple"),
    ("carbs",    "glucides",  "bolt.fill",   "orange"),
    ("calories", "calories",  "flame.fill",  "red"),
]


def _scan_family_C(ex_by_date: dict, context: dict) -> list[dict]:
    patterns = []
    seen: set[str] = set()

    for exercise, date_vol in ex_by_date.items():
        if len(date_vol) < 14:
            continue

        for nutr_key, nutr_label, icon, color in _NUTR_META:
            key = f"C__{exercise}__{nutr_key}"
            if key in seen:
                continue

            xs, ys = [], []
            for d, vol in date_vol.items():
                try:
                    prev_d = (date_cls.fromisoformat(d) - timedelta(days=1)).isoformat()
                except ValueError:
                    continue
                nv = context.get(prev_d, {}).get(nutr_key)
                if nv is None or nv <= 0:
                    continue
                xs.append(float(nv))
                ys.append(float(vol))

            if len(xs) < 14:
                continue
            r = _pearson(xs, ys)
            if r is None or not _ok_r(r, len(xs)):
                continue

            # Tertile comparison for human-readable effect
            n3 = max(1, len(xs) // 3)
            pairs = sorted(zip(xs, ys))
            lo_y = [y for _, y in pairs[:n3]]
            hi_y = [y for _, y in pairs[-n3:]]
            avg_lo, avg_hi = _mean(lo_y), _mean(hi_y)
            if avg_lo < 1e-6:
                continue
            pct = (avg_hi - avg_lo) / avg_lo * 100
            if abs(pct) < 5:
                continue

            seen.add(key)
            direction = "augmente" if pct > 0 else "baisse"
            max_avg   = max(avg_hi, avg_lo)
            _NUTR_UNIT = {"protein": "g", "carbs": "g", "calories": "kcal"}
            _NUTR_MACRO_KEY = {"protein": "proteines", "carbs": "glucides", "calories": "calories"}
            patterns.append({
                "id":         key,
                "family":     "C",
                "sub_label":  "Nutrition → Perf",
                "headline":   f"Quand tu consommes plus de {nutr_label} la veille, ton volume au {exercise.title()} {direction} de {abs(int(pct))}% en moyenne",
                "confidence": _confidence(r, len(xs)),
                "effect_pct": round(abs(pct), 1),
                "n":          len(xs),
                "metric_r":   r,
                "bar_a":      {"label": f"{nutr_label} élevés",  "value": round(avg_hi, 1), "frac": round(avg_hi / max_avg, 3)},
                "bar_b":      {"label": f"{nutr_label} faibles", "value": round(avg_lo, 1), "frac": round(avg_lo / max_avg, 3)},
                "icon":       icon,
                "color":      color,
                "macro_threshold": {
                    "macro": _NUTR_MACRO_KEY[nutr_key],
                    "value": round(avg_hi, 1),
                    "unit":  _NUTR_UNIT[nutr_key],
                },
            })

    return patterns


# ── Family D: Skip → Stress ────────────────────────────────────────────────────

def _scan_family_D(sessions: list[dict], context: dict) -> list[dict]:
    week_dates: dict[str, list[str]] = defaultdict(list)
    week_pss:   dict[str, list[float]] = defaultdict(list)

    for s in sessions:
        d = str(s.get("date") or "")[:10]
        if not d:
            continue
        try:
            iso = date_cls.fromisoformat(d).isocalendar()
            wk  = f"{iso.year}-W{iso.week:02d}"
        except ValueError:
            continue
        week_dates[wk].append(d)

    for d, ctx in context.items():
        pss = ctx.get("pss_score")
        if pss is None:
            continue
        try:
            iso = date_cls.fromisoformat(d).isocalendar()
            wk  = f"{iso.year}-W{iso.week:02d}"
        except ValueError:
            continue
        week_pss[wk].append(pss)

    counts = [len(v) for v in week_dates.values() if len(v) > 0]
    if not counts:
        return []
    expected = sorted(counts)[len(counts) // 2]
    if expected < 2:
        return []

    common_weeks = sorted(set(week_dates) & set(week_pss))
    if len(common_weeks) < 8:
        return []

    xs = [float(max(0, expected - len(week_dates[w]))) for w in common_weeks]
    ys = [_mean(week_pss[w]) for w in common_weeks]

    r = _pearson(xs, ys)
    if r is None or not _ok_r(r, len(xs)):
        return []

    no_skip  = [y for x, y in zip(xs, ys) if x == 0]
    hi_skip  = [y for x, y in zip(xs, ys) if x >= 2]
    if len(no_skip) < 3 or len(hi_skip) < 3:
        return []

    avg_ns = _mean(no_skip)
    avg_hs = _mean(hi_skip)
    if avg_ns < 1e-6:
        return []
    pct = (avg_hs - avg_ns) / avg_ns * 100
    if abs(pct) < 5:
        return []

    max_pss = max(avg_ns, avg_hs)
    return [{
        "id":         "D__skip_stress",
        "family":     "D",
        "sub_label":  "Régularité → Stress",
        "headline":   f"Ton stress monte de {abs(int(pct))}% les semaines où tu skip 2 séances ou plus",
        "confidence": _confidence(r, len(common_weeks)),
        "effect_pct": round(abs(pct), 1),
        "n":          len(common_weeks),
        "metric_r":   r,
        "bar_a":      {"label": "Semaines régulières",   "value": round(avg_ns, 1), "frac": round(avg_ns / max_pss, 3)},
        "bar_b":      {"label": "2+ séances manquées",   "value": round(avg_hs, 1), "frac": round(avg_hs / max_pss, 3)},
        "icon":       "calendar.badge.exclamationmark",
        "color":      "red",
    }]


# ── Family E: War Room × Activité physique ────────────────────────────────────

def _scan_family_E(context: dict, sess_corr: dict) -> list[dict]:
    """Cohen's d: trigger_count/intensity on days with vs. without a workout session."""
    workout_days = set(sess_corr.keys())
    with_wk_triggers:   list[float] = []
    with_wk_intensity:  list[float] = []
    no_wk_triggers:     list[float] = []
    no_wk_intensity:    list[float] = []

    for d, ctx in context.items():
        tc = ctx.get("trigger_count")
        ti = ctx.get("trigger_intensity")
        if tc is None:
            continue
        if d in workout_days:
            with_wk_triggers.append(float(tc))
            if ti is not None:
                with_wk_intensity.append(float(ti))
        else:
            no_wk_triggers.append(float(tc))
            if ti is not None:
                no_wk_intensity.append(float(ti))

    patterns: list[dict] = []

    # E1 — trigger count
    if len(with_wk_triggers) >= 5 and len(no_wk_triggers) >= 5:
        d_val = _cohen_d(no_wk_triggers, with_wk_triggers)  # no-workout group first (expect higher)
        if _ok_d(d_val, min(len(with_wk_triggers), len(no_wk_triggers))):
            avg_wk  = _mean(with_wk_triggers)
            avg_nwk = _mean(no_wk_triggers)
            ref = min(avg_wk, avg_nwk)
            if ref > 1e-6:
                pct = (avg_nwk - avg_wk) / ref * 100
                if abs(pct) >= 5:
                    direction = "moins" if pct > 0 else "plus"
                    hi, lo = max(avg_wk, avg_nwk), min(avg_wk, avg_nwk)
                    patterns.append({
                        "id":         "E__trigger_count_workout",
                        "family":     "E",
                        "war_room":   True,
                        "sub_label":  "War Room × Sport",
                        "headline":   f"Tu déclenches {abs(int(pct))}% {direction} de triggers War Room les jours où tu t'entraînes",
                        "confidence": _confidence(d_val, min(len(with_wk_triggers), len(no_wk_triggers))),
                        "effect_pct": round(abs(pct), 1),
                        "n":          len(with_wk_triggers) + len(no_wk_triggers),
                        "metric_d":   round(d_val, 3),
                        "bar_a":      {"label": "Jour d'entraînement",  "value": round(avg_wk, 1), "frac": round(avg_wk / hi, 3)},
                        "bar_b":      {"label": "Jour sans entraînement", "value": round(avg_nwk, 1), "frac": round(avg_nwk / hi, 3)},
                        "icon":       "bolt.heart.fill",
                        "color":      "red",
                    })

    # E2 — trigger intensity
    if len(with_wk_intensity) >= 5 and len(no_wk_intensity) >= 5:
        d_val = _cohen_d(no_wk_intensity, with_wk_intensity)
        if _ok_d(d_val, min(len(with_wk_intensity), len(no_wk_intensity))):
            avg_wk  = _mean(with_wk_intensity)
            avg_nwk = _mean(no_wk_intensity)
            ref = min(avg_wk, avg_nwk)
            if ref > 1e-6:
                pct = (avg_nwk - avg_wk) / ref * 100
                if abs(pct) >= 5:
                    direction = "moins" if pct > 0 else "plus"
                    hi = max(avg_wk, avg_nwk)
                    patterns.append({
                        "id":         "E__trigger_intensity_workout",
                        "family":     "E",
                        "war_room":   True,
                        "sub_label":  "War Room × Sport",
                        "headline":   f"L'intensité de tes triggers War Room est {abs(int(pct))}% {direction} élevée les jours d'entraînement",
                        "confidence": _confidence(d_val, min(len(with_wk_intensity), len(no_wk_intensity))),
                        "effect_pct": round(abs(pct), 1),
                        "n":          len(with_wk_intensity) + len(no_wk_intensity),
                        "metric_d":   round(d_val, 3),
                        "bar_a":      {"label": "Jour d'entraînement",    "value": round(avg_wk, 1),  "frac": round(avg_wk / hi, 3)},
                        "bar_b":      {"label": "Jour sans entraînement", "value": round(avg_nwk, 1), "frac": round(avg_nwk / hi, 3)},
                        "icon":       "exclamationmark.triangle.fill",
                        "color":      "orange",
                    })

    return patterns


# ── Family F: Spirit × Mind ────────────────────────────────────────────────────

def _scan_family_F(context: dict) -> list[dict]:
    """Cohen's d: PSS and soreness on breathwork/meditation days vs. rest."""
    bw_pss:  list[float] = []
    nbw_pss: list[float] = []
    bw_sor:  list[float] = []
    nbw_sor: list[float] = []
    md_pss:  list[float] = []
    nmd_pss: list[float] = []
    md_sor:  list[float] = []
    nmd_sor: list[float] = []

    for d, ctx in context.items():
        bw = ctx.get("breathwork_done", 0.0)
        md = ctx.get("meditation_done", 0.0)
        pss = ctx.get("pss_score")
        sor = ctx.get("soreness")
        if pss is not None:
            (bw_pss if bw > 0 else nbw_pss).append(float(pss))
            (md_pss if md > 0 else nmd_pss).append(float(pss))
        if sor is not None:
            (bw_sor if bw > 0 else nbw_sor).append(float(sor))
            (md_sor if md > 0 else nmd_sor).append(float(sor))

    patterns: list[dict] = []

    def _spirit_pattern(pid: str, with_g: list[float], no_g: list[float],
                         label_with: str, label_no: str,
                         metric_name: str, icon: str, color: str,
                         lower_is_better: bool = True):
        if len(with_g) < 5 or len(no_g) < 5:
            return
        # Positive d → with_g mean > no_g mean
        d_val = _cohen_d(with_g, no_g)
        if not _ok_d(d_val, min(len(with_g), len(no_g))):
            return
        avg_w, avg_n = _mean(with_g), _mean(no_g)
        ref = min(avg_w, avg_n)
        if ref < 1e-6:
            return
        pct = (avg_n - avg_w) / ref * 100  # positive → practice reduces metric
        if abs(pct) < 5:
            return
        benefit = (pct > 0) == lower_is_better  # True → practice helps
        direction = "réduit" if benefit else "augmente"
        hi = max(avg_w, avg_n)
        patterns.append({
            "id":         pid,
            "family":     "F",
            "sub_label":  "Spirit × Mind",
            "headline":   f"Ta pratique {direction} ton {metric_name} de {abs(int(pct))}% en moyenne",
            "confidence": _confidence(d_val, min(len(with_g), len(no_g))),
            "effect_pct": round(abs(pct), 1),
            "n":          len(with_g) + len(no_g),
            "metric_d":   round(d_val, 3),
            "bar_a":      {"label": label_with, "value": round(avg_w, 1), "frac": round(avg_w / hi, 3)},
            "bar_b":      {"label": label_no,   "value": round(avg_n, 1), "frac": round(avg_n / hi, 3)},
            "icon":       icon,
            "color":      color,
        })

    _spirit_pattern("F__breathwork_pss",       bw_pss,  nbw_pss, "Jours breathwork", "Jours sans",
                    "PSS", "wind", "teal", lower_is_better=True)
    _spirit_pattern("F__breathwork_soreness",   bw_sor,  nbw_sor, "Jours breathwork", "Jours sans",
                    "courbatures", "bolt.heart.fill", "blue", lower_is_better=True)
    _spirit_pattern("F__meditation_pss",        md_pss,  nmd_pss, "Jours méditation", "Jours sans",
                    "PSS", "brain.head.profile", "purple", lower_is_better=True)
    _spirit_pattern("F__meditation_soreness",   md_sor,  nmd_sor, "Jours méditation", "Jours sans",
                    "courbatures", "figure.mind.and.body", "indigo", lower_is_better=True)

    return patterns


# ── Family G: War Room reset × Training J+1 ───────────────────────────────────

def _scan_family_G(context: dict, sess_corr: dict) -> list[dict]:
    """Compare session volume and RPE the day after a War Room reset (lost battle)."""
    vol_after_reset:  list[float] = []
    rpe_after_reset:  list[float] = []
    vol_after_normal: list[float] = []
    rpe_after_normal: list[float] = []

    sorted_dates = sorted(context.keys())
    for i, d in enumerate(sorted_dates[:-1]):
        next_d = sorted_dates[i + 1]
        is_reset = context[d].get("is_reset_day", 0.0) > 0
        s = sess_corr.get(next_d, {})
        vol = s.get("session_volume")
        rpe = s.get("rpe")
        if vol is not None:
            (vol_after_reset if is_reset else vol_after_normal).append(float(vol))
        if rpe is not None:
            (rpe_after_reset if is_reset else rpe_after_normal).append(float(rpe))

    patterns: list[dict] = []

    def _reset_pattern(pid: str, after_r: list[float], after_n: list[float],
                        metric_label: str, icon: str, color: str, lower_good: bool = False):
        if len(after_r) < 3 or len(after_n) < 5:
            return
        d_val = _cohen_d(after_r, after_n)
        if abs(d_val) < 0.4 or min(len(after_r), len(after_n)) < 3:
            return
        avg_r, avg_n = _mean(after_r), _mean(after_n)
        ref = min(avg_r, avg_n)
        if ref < 1e-6:
            return
        pct = (avg_r - avg_n) / ref * 100
        if abs(pct) < 5:
            return
        hi = max(avg_r, avg_n)
        direction = "inférieur" if pct < 0 else "supérieur"
        patterns.append({
            "id":         pid,
            "family":     "G",
            "war_room":   True,
            "sub_label":  "War Room reset → J+1",
            "headline":   f"Ton {metric_label} du lendemain est {abs(int(pct))}% {direction} après un jour de reset War Room",
            "confidence": _confidence(d_val, min(len(after_r), len(after_n))),
            "effect_pct": round(abs(pct), 1),
            "n":          len(after_r) + len(after_n),
            "metric_d":   round(d_val, 3),
            "bar_a":      {"label": "Après reset",  "value": round(avg_r, 1), "frac": round(avg_r / hi, 3)},
            "bar_b":      {"label": "Après journée normale", "value": round(avg_n, 1), "frac": round(avg_n / hi, 3)},
            "icon":       icon,
            "color":      color,
        })

    _reset_pattern("G__reset_volume_j1", vol_after_reset, vol_after_normal,
                   "volume", "dumbbell.fill", "red")
    _reset_pattern("G__reset_rpe_j1", rpe_after_reset, rpe_after_normal,
                   "RPE", "gauge.high", "orange")

    return patterns


# ── Priority scoring ───────────────────────────────────────────────────────────

_ACTIONABILITY = {"A": 1.0, "C": 0.95, "F": 0.9, "B": 0.7, "D": 0.6, "E": 0.5, "G": 0.5}


def _score(p: dict, shown: set[str]) -> float:
    effect   = min(1.0, p.get("effect_pct", 0) / 40.0)
    strength = abs(p.get("metric_r") or p.get("metric_d") or 0.0)
    novelty  = 0.0 if p["id"] in shown else 1.0
    action   = _ACTIONABILITY.get(p.get("family", ""), 0.5)
    return effect * 0.3 + strength * 0.3 + novelty * 0.3 + action * 0.1


# ── State (SQLite local; no-op on Vercel — acceptable for MVP) ─────────────────

def _load_state() -> dict:
    raw, _, _ = db._sqlite_get("pattern_state")
    if isinstance(raw, dict):
        return raw
    return {"shown_log": [], "pinned": []}


def _save_state(state: dict) -> None:
    db._sqlite_set("pattern_state", state, dirty=1)


# ── 24h in-process cache ──────────────────────────────────────────────────────

_CACHE: dict = {}
_CACHE_TTL = 24 * 3600


def _get_all_patterns() -> list[dict]:
    now    = _time.time()
    cached = _CACHE.get("patterns")
    if cached and (now - cached["ts"]) < _CACHE_TTL:
        return cached["data"]
    data = _compute_all()
    _CACHE["patterns"] = {"data": data, "ts": now}
    return data


def _compute_all() -> list[dict]:
    try:
        context    = _load_context(days=90)
        ex_by_date = _load_ex_by_date(days=90)

        sess_corr   = db.get_sessions_for_correlations(days=90)
        raw_sessions = db.get_workout_sessions(limit=200)
        for s in raw_sessions:
            d = str(s.get("date") or "")[:10]
            if d in sess_corr:
                s.setdefault("session_volume", sess_corr[d].get("session_volume"))

        patterns: list[dict] = []
        patterns.extend(_scan_family_A(ex_by_date, context))
        patterns.extend(_scan_family_B(raw_sessions))
        patterns.extend(_scan_family_C(ex_by_date, context))
        patterns.extend(_scan_family_D(
            [{"date": d, **v} for d, v in sess_corr.items()],
            context,
        ))
        patterns.extend(_scan_family_E(context, sess_corr))
        patterns.extend(_scan_family_F(context))
        patterns.extend(_scan_family_G(context, sess_corr))

        dummy: set[str] = set()
        patterns.sort(key=lambda p: _score(p, dummy), reverse=True)
        return patterns
    except Exception as e:
        logger.exception("pattern_engine._compute_all failed: %s", e)
        return []


# ── Trend computation ─────────────────────────────────────────────────────────

def _compute_trend(pattern: dict, shown_log: list[dict]) -> dict | None:
    """Compare current effect_pct to the value stored when pattern was first shown."""
    pid = pattern["id"]
    first = next((e for e in shown_log if e.get("id") == pid and e.get("effect_pct") is not None), None)
    if first is None:
        return None
    initial = float(first["effect_pct"])
    current = float(pattern.get("effect_pct", 0))
    delta   = round(current - initial, 1)
    if abs(delta) < 1:
        direction = "stable"
    elif delta > 0:
        direction = "rising"
    else:
        direction = "falling"
    return {
        "direction":   direction,
        "delta_pct":   delta,
        "initial_pct": round(initial, 1),
        "current_pct": round(current, 1),
    }


# ── Public API ─────────────────────────────────────────────────────────────────

def get_daily_pattern() -> dict:
    all_patterns = _get_all_patterns()
    state        = _load_state()
    shown_log    = state.get("shown_log", [])
    shown_ids    = {e["id"] for e in shown_log}
    pinned_set   = set(state.get("pinned", []))
    today        = date_cls.fromisoformat(_today_mtl()).isoformat()
    cutoff_45    = (date_cls.fromisoformat(_today_mtl()) - timedelta(days=45)).isoformat()

    # War Room patterns are sandboxed — exclude from daily rotation
    eligible = [p for p in all_patterns if not p.get("war_room")]

    # Attach pinned flag and is_new (never shown before)
    all_shown_ids_ever = {e["id"] for e in shown_log}
    tagged = [{**p, "pinned": p["id"] in pinned_set, "is_new": p["id"] not in all_shown_ids_ever}
              for p in eligible]

    # Pick daily: one per calendar day, novelty-prioritised
    shown_today_entry = next(
        (e for e in shown_log if e.get("date") == today), None
    )
    daily = None
    if shown_today_entry:
        daily = next((p for p in tagged if p["id"] == shown_today_entry["id"]), None)
    else:
        candidates = [p for p in tagged if p["id"] not in shown_ids]
        if not candidates:
            candidates = tagged  # all seen → loop
        candidates.sort(key=lambda p: _score(p, shown_ids), reverse=True)
        if candidates:
            daily = candidates[0]
            state["shown_log"] = [
                e for e in shown_log if e.get("date", "") > cutoff_45
            ]
            state["shown_log"].append({
                "id":         daily["id"],
                "date":       today,
                "effect_pct": daily.get("effect_pct"),
            })
            _save_state(state)

    # Pinned patterns with trend
    pinned_patterns = []
    for p in tagged:
        if p["id"] not in pinned_set:
            continue
        trend = _compute_trend(p, state["shown_log"])
        pinned_patterns.append({**p, "trend": trend})

    return {
        "daily":        daily,
        "pinned":       pinned_patterns,
        "total":        len(eligible),
        "computed_at":  datetime.now(timezone.utc).isoformat(),
    }


def get_war_room_patterns() -> list[dict]:
    """Return War Room-specific patterns (families E and G). Sandboxed."""
    all_patterns = _get_all_patterns()
    state        = _load_state()
    shown_log    = state.get("shown_log", [])
    pinned_set   = set(state.get("pinned", []))
    all_shown_ids_ever = {e["id"] for e in shown_log}

    wr_patterns = [p for p in all_patterns if p.get("war_room")]
    result = []
    for p in wr_patterns:
        trend = _compute_trend(p, shown_log)
        result.append({
            **p,
            "pinned": p["id"] in pinned_set,
            "is_new":  p["id"] not in all_shown_ids_ever,
            "trend":   trend,
        })
    return result


def pin_pattern(pattern_id: str) -> None:
    state = _load_state()
    if pattern_id not in state["pinned"]:
        state["pinned"].append(pattern_id)
        _save_state(state)


def unpin_pattern(pattern_id: str) -> None:
    state = _load_state()
    state["pinned"] = [p for p in state["pinned"] if p != pattern_id]
    _save_state(state)


def invalidate_cache() -> None:
    _CACHE.clear()
