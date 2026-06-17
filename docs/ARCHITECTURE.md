# Architecture — TrainingOS

## Vue d'ensemble

TrainingOS est une **app iOS native SwiftUI** connectée à un **backend Flask serverless** sur Vercel, avec **Supabase (PostgreSQL)** comme base de données cloud.

```
iPhone (SwiftUI)
      │
      ▼
Flask (Vercel Serverless)
      │
   Supabase (PostgreSQL — ≥54 tables relationnelles)
```

---

## Stack technique

| Couche | Technologie |
|---|---|
| iOS | Swift 5.9 · SwiftUI · SwiftData |
| Réseau iOS | URLSession · async/await |
| Santé | HealthKit (steps, sommeil, HRV, FC, workouts) |
| Cache iOS | CacheService (TTL disque, par clé) |
| Offline iOS | SyncManager (SwiftData → retry queue) |
| Backend | Python 3 · Flask 3.1 |
| Déploiement | Vercel (serverless, `api/index.py`) |
| Base données | Supabase (PostgreSQL) |
| IA | Claude Sonnet 4.6 (coach, narrative, peak) |

---

## Structure iOS (`TrainingOS/`)

```
TrainingOS/
├── TrainingOSApp.swift          — Entry point, SyncManager + HealthKit background
├── ContentView.swift            — TabView navigation principale
│
├── Models/
│   └── APIModels.swift          — Tous les structs Codable
│
├── Services/
│   ├── APIService.swift         — Couche réseau (fetch + offlinePost)
│   ├── APIService+*.swift       — 20 extensions par domaine (Workout, Readiness, Stats, Coach…)
│   ├── CacheService.swift       — Cache TTL disque par clé
│   ├── HealthKitService.swift   — Lecture Apple Health
│   ├── WatchSyncService.swift   — Sync Watch → Supabase (30 min dedup)
│   ├── NetworkMonitor.swift     — Détection offline (NWPathMonitor)
│   ├── SyncManager.swift        — Queue mutations offline (SwiftData)
│   ├── PendingMutation.swift    — Modèle SwiftData mutation en attente
│   ├── DailyBriefService.swift  — Briefing coach 1×/jour (cache UserDefaults par date)
│   └── UnitSettings.swift       — Préférences unités (kg/lbs)
│
└── Views/
    ├── Dashboard/               — Aujourd'hui : ~20 cards analytiques (Readiness, CoachBrief, TrainingLoad, Sleep, Nutrition, WarRoom strip, etc.)
    ├── Seance/                  — Logging séance (séries, poids, RPE, RIR)
    ├── Historique/              — Historique par date
    ├── Stats/                   — Graphiques 5 onglets (volume, 1RM, groupes, cardio, corps)
    ├── Intelligence/            — Coach IA (propositions, insights, narrative)
    ├── Recovery/                — Récupération (sommeil, FC, HRV)
    ├── BodyComp/                — Poids corporel + tendance
    ├── Cardio/                  — Log cardio
    ├── MentalHealth/            — Mood, journal, breathwork, PSS
    ├── Programme/               — Planning hebdomadaire
    ├── Inventaire/              — Gestion exercices
    └── …                        — Timer, HIIT, Objectifs, XP, Notes, Profil
```

---

## Structure backend (`api/`)

```
api/
├── index.py              — Entry point Vercel, registration des 78 blueprints
├── db.py / db_*.py       — Couche données Supabase (db_sessions, db_body, db_exercises, etc.)
├── utils.py              — _today_mtl(), _now_mtl() — helpers partagés (~70 imports)
├── routes/               — 78 blueprints Flask (1 fichier par domaine)
│   ├── daily_brief.py    — GET /api/coach/daily_brief (briefing quotidien)
│   ├── readiness.py      — GET /api/readiness (source de vérité readiness)
│   ├── analytics_stats.py— GET /api/stats/streaks (streak canonique)
│   └── … (75 autres)
└── *_engine.py           — Moteurs analytiques (acwr, readiness, plateau, pr_tracker,
                            war_room, season, spirit, rupture, comeback_arc, etc.)
```

---

## ACWR — Charge aiguë/chronique (`acwr.py`)

### Algorithme : EWMA (Blanch & Gabbett 2016)

```
EWMA_t = λ × load_t + (1 − λ) × EWMA_{t−1}
λ = 2 / (N + 1)

acute  : N=7  → λ=0.250  (half-life ≈ 2.4 jours)
chronic: N=28 → λ≈0.069  (half-life ≈ 9.7 jours)
ACWR = EWMA_acute / EWMA_chronic
```

Les deux EWMA sont **indépendants** — pas de couplage mathématique (contrairement aux rolling averages où acute ⊂ chronic).

### Charge de séance

| Données disponibles | Formule |
|---|---|
| sRPE + durée | `sRPE × duration_min` (Foster 2001) |
| Tonnage seulement | `log(1 + tonnage_kg) × 10` (fallback) |

### Garde-fous

| Garde-fou | Valeur |
|---|---|
| Cap outliers | `mean + 3σ` (sur charges non-nulles, ≥5 points) |
| Plancher chronique | `1.0 AU` (évite division par zéro) |
| Clamp ratio | `[0.0, 3.0]` |
| Confiance `"low"` | ratio forcé à 1.0 (< 7 jours) |

### Zones

| Ratio | Zone | Code |
|---|---|---|
| < 0.8 | Sous-charge | `under` |
| 0.8–1.3 | Optimal | `optimal` |
| 1.3–1.5 | Attention | `caution` |
| > 1.5 | Surcharge | `danger` |

### Réponse API (`GET /api/acwr`)

```json
{
  "ratio": 1.12,
  "acute_load": 145.3,
  "chronic_load": 129.7,
  "zone": { "code": "optimal", "label": "Zone optimale", "color": "#10B981", "recommendation": "…" },
  "trend": [ { "week": "W1", "ratio": 0.95, "acute": 120, "chronic": 126 }, … ],
  "confidence": "high",
  "days_of_data": 42
}
```

---

## Algorithme de progression (`progression.py`)

### RPE gradué (5 niveaux)

| RPE | Action |
|---|---|
| ≤ 5.5 | +incrément complet |
| 5.6–6.5 | +demi-incrément |
| 6.6–7.9 | maintien (ou +demi si trend ≤ 0 sur 4 semaines) |
| 8.0–8.9 | −demi-incrément |
| ≥ 9.0 | −incrément complet |

### RIR (Reps In Reserve)
Quand RPE absent : `rpe_approx = 10 − avg_rir`. RIR 0 ≈ RPE 10, RIR 4 ≈ RPE 6.

### Trend analysis 4 semaines
`compute_progression_rate(history)` : régression linéaire sur les 1RM des 28 derniers jours → lbs/semaine. Si trend ≤ 0 en zone "maintain" → nudge +demi-incrément.

---

## Détection deload (`deload.py`)

3 signaux indépendants, OR-combinés :

| Signal | Condition | Seuil |
|---|---|---|
| Stagnation | Même poids N séances de suite | 3 séances |
| Fatigue RPE | RPE moyen 3 séances ≥ seuil | 8.5 |
| Chute 1RM | Drop ≥ 10% sur 3 séances | 10% |

Si ≥ 1 signal : `recommande = True` → deload à −15%.

---

## Coach IA (`IntelligenceView` + `DailyBriefService`)

**Briefing quotidien (remplace le chat) :**
- `Services/DailyBriefService.swift` — cache UserDefaults keyed par date (`daily_brief_v1_data`)
- `GET /api/coach/daily_brief` (`api/routes/daily_brief.py`) — génération Claude Sonnet 4.6
- Si la date n'a pas changé, le cache est servi sans appel réseau

**Endpoints analytiques actifs :**
- Narrative semaine : `POST /api/ai/narrative` (cache par clé `narrative_YYYY-WXX`)
- Peak prediction : `GET /api/peak_prediction` (régression 14j LSS, projeté 7j)
- Contexte athlete : ~1400 chars (format terse : LSS, ACWR, sessions, 1RM, groupes musculaires)

---

## Couche données iOS

### CacheService (TTL disque)

Clés importantes :

| Clé | Contenu | Invalidé après |
|---|---|---|
| `dashboard` | DashboardData | logExercise, logSession |
| `seance_data` | SeanceData | logExercise (matin) |
| `seance_soir_data` | SeanceData | logExercise (soir) |
| `stats_data` | StatsData | logSession |
| `historique_data` | HistoriqueData | logSession, deleteSession |
| `peak_prediction` | [PeakDay] | 24h TTL |

### SyncManager (offline-first)

SwiftData persiste les mutations en attente (`PendingMutation`).
Au retour en ligne : retry FIFO jusqu'à succès 2xx.
409 "already_logged" traité comme succès (idempotent).

---

## Flow Apple Watch → Supabase

```
Apple Watch
  └── HealthKit (iPhone)
        └── HealthKitService.fetchTodayHealthSnapshot()
              └── WatchSyncService.sync()
                    └── APIService.syncWearableData()
                          └── POST /api/wearable/sync
                                ├── recovery_logs
                                ├── cardio_logs
                                └── body_weight_logs
```
