"""
VinceSeven MCP — version analytique profonde.
3 outils riches. Appels parallèles. Zéro recalcul.
"""
import asyncio
import os
from datetime import datetime, timedelta, date as date_cls

import httpx
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("VinceSeven Training")

BASE_URL = "https://training-os-rho.vercel.app"


def _headers() -> dict:
    key = os.getenv("TRAININGOS_API_KEY", "")
    return {"Authorization": f"Bearer {key}"}


async def _fetch(client: httpx.AsyncClient, path: str, params: dict | None = None) -> dict:
    """GET sécurisé — retourne {"_error": ...} sans crasher."""
    try:
        r = await client.get(f"{BASE_URL}{path}", params=params, timeout=20)
        r.raise_for_status()
        return r.json()
    except Exception as e:
        return {"_error": str(e)}


async def _post(client: httpx.AsyncClient, path: str, body: dict | None = None) -> dict:
    """POST sécurisé — retourne {"_error": ...} sans crasher."""
    try:
        r = await client.post(f"{BASE_URL}{path}", json=body or {}, timeout=20)
        r.raise_for_status()
        return r.json()
    except Exception as e:
        return {"_error": str(e)}


# ─────────────────────────────────────────────────────────────────────────────
# Outil 0 — Écriture deload
# ─────────────────────────────────────────────────────────────────────────────

@mcp.tool()
async def set_deload(action: str, user_quote: str, reason: str = "Repos volontaire", duration_days: int = 7) -> str:
    """
    Active ou désactive la décharge volontaire de Vince dans TrainingOS.

    ⚠️  N'appelle JAMAIS cet outil de ta propre initiative.
    Appelle-le UNIQUEMENT quand Vince demande explicitement d'activer
    ou désactiver un deload. Avant d'appeler, résume en langage naturel
    l'action prévue (action, raison, durée) et attends sa confirmation
    claire. Si Vince n'a pas dit "oui", "go", ou une approbation
    explicite, n'appelle pas cet outil.

    action     : "activate" ou "deactivate" — toute autre valeur est rejetée.
    user_quote : la phrase EXACTE et VERBATIM par laquelle Vince a demandé ce
                 deload. Ne JAMAIS paraphraser, inventer ou déduire. Si Vince
                 n'a pas explicitement demandé d'activer/désactiver un deload,
                 tu n'as pas de user_quote valide — donc n'appelle pas l'outil.
                 Une évocation comme "je suis fatigué" n'est PAS une demande
                 de deload. Paramètre obligatoire, sans valeur par défaut.
    reason     : raison du repos (ex: "Fatigue accumulée"). Ignoré si deactivate.
    duration_days : durée en jours entre 1 et 21, clampé automatiquement.
    """
    if action not in ("activate", "deactivate"):
        return f"❌ Paramètre action invalide : '{action}'. Valeurs acceptées : 'activate' ou 'deactivate'."

    duration_days = max(1, min(21, duration_days))
    path = f"/api/deload/{action}"
    body = {"reason": reason, "duration_days": duration_days} if action == "activate" else {}

    async with httpx.AsyncClient(headers=_headers()) as client:
        result = await _post(client, path, body)
        if not _ok(result):
            return f"❌ Échec {action} deload : {_err(result)}"
        status = await _fetch(client, "/api/deload/status")

    if not _ok(status):
        return f"✅ {action} effectué (réponse API : {result}) — mais vérification état échouée : {_err(status)}"

    active    = status.get("active", False)
    started   = status.get("started_at", "?")
    ends_at   = status.get("ends_at", "?")
    days_r    = status.get("days_remaining")
    completed = status.get("last_completed", "?")

    if action == "activate":
        if not active:
            return f"⚠️  POST réussi mais état en base = inactif — vérifier manuellement."
        days_info = f", {days_r} jour(s) restant(s)" if days_r is not None else ""
        return (
            f"✅ Deload activé.\n"
            f"  Demande Vince : \"{user_quote}\"\n"
            f"  Raison        : {reason}\n"
            f"  Durée         : {duration_days} jour(s)\n"
            f"  Début         : {started}\n"
            f"  Fin prévue    : {ends_at}{days_info}\n"
            f"  État en base  : active={active} (vérifié)"
        )
    else:
        if active:
            return f"⚠️  POST réussi mais état en base = encore actif — vérifier manuellement."
        return (
            f"✅ Deload désactivé.\n"
            f"  Demande Vince : \"{user_quote}\"\n"
            f"  Complété le   : {completed}\n"
            f"  État en base  : active={active} (vérifié)"
        )


def _ok(d: dict) -> bool:
    return isinstance(d, dict) and "_error" not in d


def _err(d: dict) -> str:
    return d.get("_error", "erreur inconnue")


# ─────────────────────────────────────────────────────────────────────────────
# Outil 1 — État complet du jour
# ─────────────────────────────────────────────────────────────────────────────

@mcp.tool()
async def get_training_status() -> str:
    """
    Retourne l'image COMPLÈTE de l'état de forme de Vincent pour aujourd'hui,
    en agrégeant quatre sources en parallèle :
      - Score de readiness (0-100) et verdict (go / moderate / rest) avec le
        détail de chacun des 9 modules (HRV, FC repos, ACWR, sommeil qualité
        et durée, ressenti subjectif, récupération musculaire, nutrition,
        pattern repos) ;
      - HRV : valeur du jour vs baseline 7j et 30j, variation en %, zone
        (green / orange / red), tendance sur 7 jours, alerte streak si ≥3
        jours consécutifs sous baseline ;
      - ACWR (charge d'entraînement) : ratio aigu/chronique, zone
        (optimal / caution / danger), trajectoire sur 8 semaines, split
        muscu vs cardio ;
      - Sommeil : dette en heures sur 7 jours, tendance (creuser / stable /
        rembourser), nuits loggées, nuits nécessaires pour récupérer.

    À utiliser pour tout diagnostic de forme : "comment je vais ?",
    "puis-je m'entraîner fort aujourd'hui ?", "suis-je en train de
    surentraîner ?", "pourquoi je me sens fatigué ?".
    """
    async with httpx.AsyncClient(headers=_headers()) as client:
        readiness, acwr, hrv, sleep, deload = await asyncio.gather(
            _fetch(client, "/api/readiness"),
            _fetch(client, "/api/acwr"),
            _fetch(client, "/api/hrv/analysis"),
            _fetch(client, "/api/sleep_debt"),
            _fetch(client, "/api/deload/status"),
        )

    today = datetime.now().strftime("%A %d %B %Y").capitalize()
    lines = [f"=== ÉTAT COMPLET DU JOUR — {today} ===", ""]

    # ── Décharge volontaire ──
    if _ok(deload) and deload.get("active"):
        reason  = deload.get("reason") or "non précisée"
        since   = deload.get("started_at", "?")
        ends_at = deload.get("ends_at", "?")
        days_r  = deload.get("days_remaining")
        lines.append(f"⚠️  DÉCHARGE VOLONTAIRE ACTIVE depuis {since} (raison : {reason})")
        lines.append(f"   Fin prévue : {ends_at}" + (f" — {days_r} jour(s) restant(s)" if days_r is not None else ""))
        lines.append("   → Faible activité cette semaine = INTENTIONNEL, pas un abandon.")
        lines.append("")

    # ── Readiness ──
    if _ok(readiness):
        score   = readiness.get("score", "?")
        verdict = (readiness.get("verdict") or "?").upper()
        why     = readiness.get("why", "")
        adj     = readiness.get("adjustment", "")
        session = readiness.get("today_session") or "—"
        lines += [
            f"READINESS : {score}/100 — {verdict}",
            f"Séance programmée : {session}",
        ]
        if why:
            lines.append(f"Verdict : {why}")
        if adj:
            lines.append(f"Note : {adj}")
        lines.append("")

        mods = readiness.get("modules", {})
        if mods:
            lines.append("MODULES READINESS :")
            labels = {
                "hrv":            "HRV             ",
                "rhr":            "FC repos         ",
                "acwr":           "Charge (ACWR)    ",
                "sleep_quality":  "Qualité sommeil  ",
                "sleep_duration": "Durée sommeil    ",
                "subjective":     "Ressenti subjectif",
                "muscle_rec":     "Récup musculaire ",
                "nutrition":      "Nutrition        ",
                "pattern":        "Pattern repos    ",
            }
            for key, label in labels.items():
                mod = mods.get(key)
                if mod:
                    lines.append(f"  {label}: {mod.get('score') or '?':>3}/100 — {mod.get('detail', '')}")
            lines.append("")
    else:
        lines.append(f"[Readiness indisponible : {_err(readiness)}]")
        lines.append("")

    # ── HRV ──
    lines.append("=== HRV (système nerveux) ===")
    if _ok(hrv):
        today_v   = hrv.get("today_rmssd")
        base7     = hrv.get("hrv_7d_avg")
        base30    = hrv.get("hrv_30d_avg")
        zone      = (hrv.get("hrv_zone") or "?").upper()
        trend     = hrv.get("hrv_trend", "?")
        streak    = hrv.get("consecutive_low_days", 0)
        alert     = hrv.get("streak_alert", False)
        cv        = hrv.get("hrv_cv")
        hist      = hrv.get("history_7d", [])
        ctx_msg   = hrv.get("contextual_message")

        pct = ""
        if today_v and base7:
            p = round((today_v - base7) / base7 * 100, 1)
            pct = f" ({'+' if p >= 0 else ''}{p}% vs baseline)"

        lines.append(f"Aujourd'hui : {today_v} ms | Baseline 7j : {base7} ms | Baseline 30j : {base30} ms")
        lines.append(f"Zone : {zone}{pct}")
        lines.append(f"Tendance 7j : {trend} | Jours sous baseline : {streak}")
        if alert:
            lines.append(f"STREAK ALERT : {streak} jours consécutifs sous baseline — SNC sous pression")
        if cv is not None:
            lines.append(f"Coefficient de variation 30j : {cv}% (instable si >20%)")
        if hist:
            hist_str = " | ".join(
                f"{h.get('date', '?')[-5:]}:{h.get('hrv', '?')}" for h in hist
            )
            lines.append(f"Historique 7j (date:ms) : {hist_str}")
        if ctx_msg:
            lines.append(f"Note : {ctx_msg}")
    else:
        lines.append(f"[HRV indisponible : {_err(hrv)}]")
    lines.append("")

    # ── ACWR ──
    lines.append("=== ACWR (charge d'entraînement) ===")
    if _ok(acwr):
        ratio    = acwr.get("ratio")
        acute    = acwr.get("acute_load")
        chronic  = acwr.get("chronic_load")
        zone_d   = acwr.get("zone", {})
        z_code   = (zone_d.get("code") or "?").upper()
        z_label  = zone_d.get("label", "")
        z_rec    = zone_d.get("recommendation", "")
        conf     = acwr.get("confidence", "?")
        trend_w  = acwr.get("trend", [])
        s_acwr   = acwr.get("strength_acwr", {})
        c_acwr   = acwr.get("cardio_acwr", {})

        lines.append(f"Ratio : {ratio} → {z_code} ({z_label})")
        lines.append(f"Charge aiguë 7j : {acute} | Charge chronique 28j : {chronic}")
        lines.append(f"Muscu : {s_acwr.get('ratio', '?')} | Cardio : {c_acwr.get('ratio', '?')} | Confiance : {conf}")
        if z_rec:
            lines.append(f"Recommandation : {z_rec}")
        if trend_w:
            t_str = " → ".join(str(w.get("ratio", "?")) for w in trend_w[-8:])
            lines.append(f"Trajectoire 8 semaines : {t_str}")
    else:
        lines.append(f"[ACWR indisponible : {_err(acwr)}]")
    lines.append("")

    # ── Sommeil ──
    lines.append("=== SOMMEIL ===")
    if _ok(sleep):
        debt7   = sleep.get("debt_7d")
        trend_s = sleep.get("trend", "?")
        avg7    = sleep.get("avg_sleep_7d")
        nights  = sleep.get("nights_to_recover")
        logged  = sleep.get("logged_7d", "?")
        has_d   = sleep.get("has_data", True)

        if not has_d:
            lines.append("Données insuffisantes (<3 nuits loggées cette semaine)")
        else:
            sign = "+" if (debt7 or 0) >= 0 else ""
            lines.append(f"Dette 7j : {sign}{debt7}h → tendance : {trend_s}")
            lines.append(f"Moyenne 7j : {avg7}h | Nuits loggées : {logged}/7")
            if nights:
                lines.append(f"Récupération nécessaire : {nights} nuit(s) pour combler la dette")
    else:
        lines.append(f"[Sommeil indisponible : {_err(sleep)}]")

    return "\n".join(lines)


# ─────────────────────────────────────────────────────────────────────────────
# Outil 2 — Analyse profonde d'un exercice
# ─────────────────────────────────────────────────────────────────────────────

@mcp.tool()
async def get_exercise_deep(exercise: str, days: int = 90) -> str:
    """
    Retourne l'analyse COMPLÈTE de la progression d'un exercice de
    musculation, en croisant trois sources :
      - Historique des 10 dernières séances : poids, reps, RPE, e1RM estimé
        (formule canonique VinceSeven), sets détaillés ;
      - Volume par session (sets × reps × poids en lbs), calculé par l'API ;
      - Contexte ACWR global pour distinguer fatigue vs vrai plateau.

    Ce que Claude peut diagnostiquer avec cet outil :
      "stagnation = fatigue (ACWR élevé + RPE en hausse + volume en baisse) ?
       ou vrai plateau (RPE stable + volume stable + e1RM plafond) ?"
      "à quelle distance du PR suis-je ? sur quelle trajectoire ?"

    Paramètre exercise : nom de l'exercice (ex: "Bench Press", "Squat",
    "Deadlift", "Overhead Press"). Doit correspondre au nom dans la base.
    Paramètre days : plage en jours pour filtrer l'historique (défaut 90).
    L'API retourne les 10 sessions les plus récentes — si elles sont toutes
    dans la plage, tout s'affiche.

    À utiliser pour tout diagnostic sur un lift spécifique : progression,
    stagnation, proximité PR, volume, effort perçu.
    """
    async with httpx.AsyncClient(headers=_headers()) as client:
        detail, weights_raw, acwr, deload = await asyncio.gather(
            _fetch(client, "/api/exercise_detail", {"name": exercise}),
            _fetch(client, "/api/weights", {"exercise": exercise}),
            _fetch(client, "/api/acwr"),
            _fetch(client, "/api/deload/status"),
        )

    cutoff = (datetime.now() - timedelta(days=days)).date()
    lines = [f"=== ANALYSE PROFONDE — {exercise.title()} ({days} derniers jours) ===", ""]

    if not _ok(detail):
        lines.append(f"[Données exercice indisponibles : {_err(detail)}]")
        return "\n".join(lines)

    e1rm_cur  = detail.get("e1rm_current")
    e1rm_best = detail.get("e1rm_best")
    in_sess   = detail.get("in_sessions", [])
    history   = detail.get("history", [])

    # Filtre par plage
    history = [
        h for h in history
        if h.get("date") and date_cls.fromisoformat(str(h["date"])[:10]) >= cutoff
    ]

    # Proximité PR
    prox = ""
    if e1rm_cur and e1rm_best and e1rm_best > 0:
        pct = round(e1rm_cur / e1rm_best * 100, 1)
        gap = round(e1rm_best - e1rm_cur, 1)
        prox = f"Proximité PR : {pct}% ({gap} lbs sous le PR)"

    lines += [
        f"e1RM actuel  : {e1rm_cur or '—'} lbs",
        f"PR all-time  : {e1rm_best or '—'} lbs",
    ]
    if prox:
        lines.append(prox)
    if in_sess:
        lines.append(f"Présent dans : {', '.join(in_sess)}")
    lines.append("")

    # ── Volume depuis /api/weights ──
    vol_by_date: dict[str, float] = {}
    sets_by_date: dict[str, int] = {}
    if _ok(weights_raw):
        ex_data = weights_raw.get(exercise) or next(iter(weights_raw.values()), {}) if weights_raw else {}
        for entry in ex_data.get("history", []):
            d = str(entry.get("date", ""))[:10]
            if not d or date_cls.fromisoformat(d) < cutoff:
                continue
            vol = entry.get("exercise_volume")
            if vol:
                vol_by_date[d] = float(vol)
            sets_list = entry.get("sets", [])
            if sets_list:
                sets_by_date[d] = len(sets_list)

    # ── Historique e1RM ──
    if history:
        lines.append("=== HISTORIQUE e1RM ===")
        lines.append(f"{'Date':<12} {'Poids':>8}  {'Reps':<6}  {'RPE':<6}  {'e1RM':>9}")
        lines.append("-" * 50)
        for h in history:
            d      = str(h.get("date", "?"))[:10]
            weight = f"{h.get('weight', '?')} lbs"
            reps   = str(h.get("reps", "?"))
            rpe    = f"RPE {h.get('rpe')}" if h.get("rpe") else "—"
            e1rm   = f"{h.get('e1rm')} lbs" if h.get("e1rm") else "—"
            lines.append(f"{d:<12} {weight:>8}  x{reps:<5}  {rpe:<6}  {e1rm:>10}")

        e1rms = [h.get("e1rm") for h in history if h.get("e1rm")]
        if len(e1rms) >= 2:
            gain = round(e1rms[0] - e1rms[-1], 1)
            sign = "+" if gain >= 0 else ""
            pct  = round(gain / e1rms[-1] * 100, 1) if e1rms[-1] else 0
            lines.append(f"\nTrend e1RM période : {sign}{gain} lbs ({sign}{pct}%)")
            lines.append(f"  Premier : {e1rms[-1]} lbs ({history[-1].get('date','?')[:10]}) → Dernier : {e1rms[0]} lbs ({history[0].get('date','?')[:10]})")
        lines.append("")

    # ── Volume ──
    if vol_by_date:
        lines.append("=== VOLUME PAR SESSION ===")
        lines.append(f"{'Date':<12} {'Volume':>12}  {'Sets':>5}")
        lines.append("-" * 35)
        for d in sorted(vol_by_date.keys(), reverse=True):
            vol  = f"{int(vol_by_date[d]):,} lbs"
            sets = sets_by_date.get(d, "?")
            lines.append(f"{d:<12} {vol:>12}  {sets:>5} sets")

        vols = list(vol_by_date.values())
        if len(vols) >= 2:
            sorted_dates = sorted(vol_by_date.keys())
            v_first = vol_by_date[sorted_dates[0]]
            v_last  = vol_by_date[sorted_dates[-1]]
            delta   = round((v_last - v_first) / v_first * 100, 1) if v_first else 0
            sign    = "+" if delta >= 0 else ""
            lines.append(f"\nTrend volume : {sign}{delta}% sur la période")
        lines.append("")

    # ── RPE ──
    rpes = [h.get("rpe") for h in history if h.get("rpe") is not None]
    if rpes:
        avg_rpe = round(sum(rpes) / len(rpes), 1)
        lines.append("=== EFFORT PERÇU (RPE) ===")
        lines.append(f"Dernier : {rpes[0]}/10 | Moyenne période : {avg_rpe}/10")
        if len(rpes) >= 3:
            recent_avg = round(sum(rpes[:3]) / 3, 1)
            old_avg    = round(sum(rpes[-3:]) / min(3, len(rpes)), 1)
            delta_rpe  = round(recent_avg - old_avg, 1)
            sign       = "+" if delta_rpe >= 0 else ""
            lines.append(f"Trend RPE (3 dernières vs 3 premières) : {sign}{delta_rpe} → {'effort en hausse' if delta_rpe > 0.3 else 'effort en baisse' if delta_rpe < -0.3 else 'effort stable'}")
        lines.append("")

    # ── Contexte ACWR ──
    lines.append("=== CONTEXTE RÉCUPÉRATION (ACWR global) ===")
    if _ok(deload) and deload.get("active"):
        lines.append(f"DÉCHARGE VOLONTAIRE active depuis {deload.get('started_at', '?')} — ACWR bas = attendu et sain.")
    if _ok(acwr):
        ratio = acwr.get("ratio")
        zone  = (acwr.get("zone", {}).get("code") or "?").upper()
        rec   = acwr.get("zone", {}).get("recommendation", "")
        lines.append(f"ACWR : {ratio} → {zone}")
        if rec:
            lines.append(f"Implication : {rec}")
    else:
        lines.append(f"[ACWR indisponible : {_err(acwr)}]")

    return "\n".join(lines)


# ─────────────────────────────────────────────────────────────────────────────
# Outil 3 — Historique & patterns
# ─────────────────────────────────────────────────────────────────────────────

@mcp.tool()
async def get_training_history(days: int = 30) -> str:
    """
    Retourne une vue analytique LARGE de l'entraînement sur N jours, en
    croisant cinq sources en parallèle :
      - Liste des séances (musculation + HIIT) avec exercices, poids, RPE ;
      - Distribution musculaire (push / pull / squat / hinge) en volume lbs
        et en nombre de séances ;
      - Tendance de volume hebdomadaire (tonnage par semaine) ;
      - Charge globale : ACWR ratio + zone + trajectoire ;
      - Risque de surentraînement (composite RPE/HRV/humeur/récupération)
        et phase du mésocycle (accumulation / intensification / réalisation /
        décharge).

    Ce que Claude peut diagnostiquer avec cet outil :
      "y a-t-il un pattern dans mes meilleures séances ?"
      "suis-je en déséquilibre musculaire (trop de push, pas assez de pull) ?"
      "mon volume augmente-t-il de façon saine ou trop vite ?"
      "lien entre RPE et moment de la journée ?"

    Paramètre days : plage d'analyse en jours (défaut 30, max 90).

    À utiliser pour tout diagnostic de pattern, tendance ou déséquilibre
    sur plusieurs semaines d'entraînement.
    """
    safe_days = min(max(days, 7), 90)

    async with httpx.AsyncClient(headers=_headers()) as client:
        sessions_raw, stats, acwr, risk, meso, deload = await asyncio.gather(
            _fetch(client, "/api/historique_data", {"limit": min(safe_days * 2, 200)}),
            _fetch(client, "/api/stats_data"),
            _fetch(client, "/api/acwr"),
            _fetch(client, "/api/overtraining_risk"),
            _fetch(client, "/api/mesocycle_status"),
            _fetch(client, "/api/deload/status"),
        )

    cutoff = (datetime.now() - timedelta(days=safe_days)).date()
    lines  = [f"=== HISTORIQUE & PATTERNS — {safe_days} derniers jours ===", ""]

    # ── Sessions dans la plage ──
    all_sessions = sessions_raw.get("session_list", []) if _ok(sessions_raw) else []
    hiit_list    = sessions_raw.get("hiit_list", [])    if _ok(sessions_raw) else []

    sessions = [
        s for s in all_sessions
        if s.get("date") and date_cls.fromisoformat(str(s["date"])[:10]) >= cutoff
    ]
    hiit = [
        h for h in hiit_list
        if h.get("date") and date_cls.fromisoformat(str(h["date"])[:10]) >= cutoff
    ]

    rpes = [s.get("rpe") for s in sessions if s.get("rpe") is not None]
    rpe_avg = round(sum(rpes) / len(rpes), 1) if rpes else None

    lines.append(f"Séances musculation : {len(sessions)} | HIIT/cardio : {len(hiit)}")
    if rpe_avg is not None:
        lines.append(f"RPE moyen : {rpe_avg}/10")
    lines.append("")

    # ── Charge & risque ──
    lines.append("=== CHARGE & RISQUE ===")
    if _ok(deload) and deload.get("active"):
        reason = deload.get("reason") or "non précisée"
        ends_at = deload.get("ends_at", "?")
        days_r = deload.get("days_remaining")
        lines.append(f"DÉCHARGE VOLONTAIRE active (raison : {reason}) — fin prévue {ends_at}" + (f", {days_r}j restant(s)" if days_r is not None else ""))
        lines.append("  → Volume bas = INTENTIONNEL. Ne pas interpréter comme décrochage.")
        lines.append("")
    if _ok(acwr):
        ratio = acwr.get("ratio")
        zone  = (acwr.get("zone", {}).get("code") or "?").upper()
        z_rec = acwr.get("zone", {}).get("recommendation", "")
        trend_w = acwr.get("trend", [])
        lines.append(f"ACWR : {ratio} → {zone}")
        if z_rec:
            lines.append(f"Note : {z_rec}")
        if trend_w:
            t_str = " → ".join(str(w.get("ratio", "?")) for w in trend_w[-6:])
            lines.append(f"Trajectoire 6 semaines : {t_str}")
    else:
        lines.append(f"[ACWR indisponible : {_err(acwr)}]")

    if _ok(risk):
        lvl   = (risk.get("level") or "?").upper()
        score = risk.get("risk_score", "?")
        flags = risk.get("flags", [])
        rec   = risk.get("recommendation", "")
        lines.append(f"Risque surentraînement : {lvl} (score {score})")
        if flags:
            lines.append(f"  Signaux : {', '.join(flags)}")
        if rec:
            lines.append(f"  Recommandation : {rec}")
    else:
        lines.append(f"[Risque indisponible : {_err(risk)}]")

    if _ok(meso):
        phase   = meso.get("phase_label", meso.get("phase", "?"))
        weeks   = meso.get("weeks_since_deload", meso.get("week_in_cycle", "?"))
        rpe_t   = meso.get("rpe_target", "")
        vol_g   = meso.get("vol_guidance", "")
        lines.append(f"Phase mésocycle : {phase} — sem. {weeks} depuis dernier deload")
        if rpe_t:
            lines.append(f"  RPE cible : {rpe_t} | {vol_g}")
    else:
        lines.append(f"[Mésocycle indisponible : {_err(meso)}]")
    lines.append("")

    # ── Distribution musculaire (depuis stats_data) ──
    lines.append("=== DISTRIBUTION MUSCULAIRE ===")
    if _ok(stats):
        pattern = stats.get("pattern_volume", {})
        if pattern:
            total_vol = sum(float(v) for v in pattern.values() if v)
            for mv, vol in sorted(pattern.items(), key=lambda x: -(x[1] or 0)):
                pct = round(float(vol) / total_vol * 100) if total_vol else 0
                lines.append(f"  {mv.capitalize():<8} : {int(vol):>8,} lbs  ({pct}%)")
        else:
            lines.append("  (données non disponibles)")
    else:
        lines.append(f"  [Stats indisponibles : {_err(stats)}]")
    lines.append("")

    # ── Volume hebdomadaire (depuis stats_data) ──
    lines.append("=== VOLUME HEBDOMADAIRE ===")
    if _ok(stats):
        tonnage = stats.get("weekly_tonnage", [])
        recent_weeks = [
            w for w in tonnage
            if w.get("week_start") and date_cls.fromisoformat(str(w["week_start"])[:10]) >= cutoff
        ][-8:]
        if recent_weeks:
            for w in recent_weeks:
                wstart = str(w.get("week_start", "?"))[:10]
                vol    = int(w.get("total_volume") or 0)
                count  = w.get("session_count", "?")
                lines.append(f"  Sem. {wstart} : {vol:>8,} lbs  ({count} séances)")
        else:
            lines.append("  (aucun tonnage disponible dans la plage)")
    else:
        lines.append(f"  [Stats indisponibles]")
    lines.append("")

    # ── RPE patterns ──
    if rpes:
        lines.append("=== RPE PATTERNS ===")
        rpe_7d  = [s.get("rpe") for s in sessions[:7] if s.get("rpe") is not None]
        avg_7   = round(sum(rpe_7d) / len(rpe_7d), 1) if rpe_7d else None
        lines.append(f"Moy {safe_days}j : {rpe_avg} | Moy 7j : {avg_7 or '—'}")

        # Distribution
        from collections import Counter
        dist = Counter(rpes)
        dist_str = "  ".join(f"RPE{k}:{v}" for k, v in sorted(dist.items()))
        lines.append(f"Distribution : {dist_str}")

        # Matin vs soir
        morning_rpes = [s.get("rpe") for s in sessions if s.get("session_type") == "morning" and s.get("rpe")]
        evening_rpes = [s.get("rpe") for s in sessions if s.get("session_type") in ("evening", "bonus") and s.get("rpe")]
        if morning_rpes and evening_rpes:
            lines.append(f"Matin : {round(sum(morning_rpes)/len(morning_rpes), 1)} moy | Soir : {round(sum(evening_rpes)/len(evening_rpes), 1)} moy")
        lines.append("")

    # ── Séances récentes (compact) ──
    lines.append("=== SÉANCES RÉCENTES ===")
    type_lbl = {"morning": "Matin", "evening": "Soir", "bonus": "Bonus"}
    for s in sessions[:15]:
        d      = str(s.get("date", "?"))[:10]
        stype  = type_lbl.get(s.get("session_type", ""), s.get("session_type", ""))
        rpe    = f" RPE {s.get('rpe')}" if s.get("rpe") else ""
        exos   = s.get("exos", [])
        ex_str = ", ".join(e.get("exercise", "?") for e in exos[:4])
        if len(exos) > 4:
            ex_str += f" (+{len(exos)-4})"
        lines.append(f"  {d}  {stype}{rpe}  — {ex_str or '(aucun exercice)'}")

    return "\n".join(lines)


# ─────────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    mcp.run()
