"""
mental_health_dashboard.py — Résumé hebdomadaire / mensuel de santé mentale.

Agrège : mood_log, journal_entries, breathwork_sessions, self_care_log, pss_records.
Aucune nouvelle clé KV — agrégation à la volée (même pattern que health_data.py).

Endpoint exposé dans index.py :
  GET /api/mental_health/summary?days=7
"""
from __future__ import annotations

from datetime import date as date_cls, timedelta

from mood       import get_history as mood_history, get_weekly_avg, get_mood_trend, EMOTIONS
from journal    import get_entry_count
from breathwork import get_stats as bw_stats, get_session_dates
from self_care  import get_completion_rate, get_streaks
from pss        import get_latest_pss_score


def get_summary(days: int = 7) -> dict:
    """
    Résumé santé mentale sur N jours.

    Retourne :
    {
      "period_days":         int,
      "avg_mood":            float | null,
      "mood_trend":          "up" | "down" | "stable",
      "mood_history":        [MoodEntry],
      "breathwork_sessions": int,
      "breathwork_minutes":  int,
      "journal_entries":     int,
      "self_care_rate":      float (0-1),
      "top_streaks":         [StreakEntry],
      "top_emotions":        [str],
      "insights":            [str],
      "correlations":        [str],
      "pss_score":           int | null,
      "pss_category":        str | null,
    }
    """
    mood_records = mood_history(days)
    bw           = bw_stats(days)
    journal_n    = get_entry_count(days)
    self_care    = get_completion_rate(days)
    streaks      = get_streaks()[:3]
    pss          = get_latest_pss_score("full") or get_latest_pss_score("short")

    avg_mood  = get_weekly_avg(days)
    trend     = get_mood_trend(days)

    # Émotions les plus fréquentes
    all_emotions: list[str] = []
    for r in mood_records:
        all_emotions.extend(r.get("emotions", []))
    emotion_counts: dict[str, int] = {}
    for e in all_emotions:
        emotion_counts[e] = emotion_counts.get(e, 0) + 1
    top_emotions = sorted(emotion_counts, key=emotion_counts.get, reverse=True)[:4]

    insights     = _generate_insights(avg_mood, trend, bw, journal_n, self_care, pss)
    correlations = _compute_correlations(mood_records, bw["sessions_count"], days)

    return {
        "period_days":         days,
        "avg_mood":            avg_mood,
        "mood_trend":          trend,
        "mood_history":        mood_records,
        "breathwork_sessions": bw["sessions_count"],
        "breathwork_minutes":  bw["total_minutes"],
        "journal_entries":     journal_n,
        "self_care_rate":      self_care,
        "top_streaks":         streaks,
        "top_emotions":        top_emotions,
        "insights":            insights,
        "correlations":        correlations,
        "pss_score":           pss.get("score")    if pss else None,
        "pss_category":        pss.get("category") if pss else None,
    }


def _generate_insights(avg_mood, trend, bw, journal_n, self_care, pss) -> list[str]:
    insights = []

    if avg_mood is not None:
        if avg_mood >= 7:
            insights.append(f"Humeur moyenne excellente à {avg_mood}/10 — t'es en feu ! 🔥")
        elif avg_mood >= 5:
            insights.append(f"Humeur moyenne correcte à {avg_mood}/10. Des petites actions peuvent faire une grosse différence.")
        else:
            insights.append(f"Humeur basse ({avg_mood}/10). C'est correct de ne pas être parfait — mais prends soin de toi.")

    if trend == "up":
        insights.append("Ta tendance d'humeur est à la hausse cette période — continue comme ça !")
    elif trend == "down":
        insights.append("L'humeur baisse un peu. Essaie d'ajouter une habitude de bien-être cette semaine.")

    if bw["sessions_count"] >= 3:
        insights.append(f"{bw['sessions_count']} sessions de respiration — excellent pour la gestion du stress !")
    elif bw["sessions_count"] == 0:
        insights.append("💡 5 min de cohérence cardiaque par jour peut réduire ton stress de façon significative.")

    if journal_n >= 4:
        insights.append(f"{journal_n} entrées de journal — l'écriture régulière aide à clarifier les émotions.")

    if self_care >= 0.7:
        insights.append(f"Taux de complétion self-care de {int(self_care*100)}% — t'es consistant(e) !")
    elif self_care < 0.3:
        insights.append("Commence par 1 habitude self-care par jour — la constance bat l'intensité.")

    if pss and pss.get("category") == "high":
        insights.append("Stress PSS élevé — les exercices de respiration et le journal peuvent vraiment aider.")

    return insights


def _compute_correlations(mood_records: list, bw_sessions: int, days: int) -> list[str]:
    """Corrélations simples humeur vs breathwork."""
    correlations = []
    if len(mood_records) < 5 or bw_sessions == 0:
        return correlations

    bw_dates = get_session_dates(days)
    mood_with_bw    = [r["score"] for r in mood_records if r.get("date") in bw_dates]
    mood_without_bw = [r["score"] for r in mood_records if r.get("date") not in bw_dates]

    if len(mood_with_bw) >= 2 and len(mood_without_bw) >= 2:
        avg_w  = sum(mood_with_bw)    / len(mood_with_bw)
        avg_wo = sum(mood_without_bw) / len(mood_without_bw)
        delta  = round(avg_w - avg_wo, 1)
        if abs(delta) >= 0.5:
            sign = "+" if delta > 0 else ""
            correlations.append(
                f"Ton humeur est {sign}{delta} pts les jours où tu fais de la respiration guidée 🧘"
            )

    return correlations
