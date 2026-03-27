# Architecture — TrainingOS

## Vue d'ensemble

TrainingOS est une **app iOS native SwiftUI** connectée à un **backend Flask serverless** sur Vercel, avec **Supabase (PostgreSQL)** comme base de données cloud.

```
iPhone (SwiftUI)
      │
      ▼
Flask (Vercel Serverless)
      │
   Supabase (PostgreSQL)
   ├── Tables relationnelles (workout_sessions, exercise_logs, …)
   └── Table KV (clé/valeur JSON pour config, inventaire, poids)
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
│   ├── CacheService.swift       — Cache TTL disque par clé
│   ├── HealthKitService.swift   — Lecture Apple Health
│   ├── WatchSyncService.swift   — Sync Watch → Supabase (30 min dedup)
│   ├── NetworkMonitor.swift     — Détection offline (NWPathMonitor)
│   ├── SyncManager.swift        — Queue mutations offline (SwiftData)
│   ├── PendingMutation.swift    — Modèle SwiftData mutation en attente
│   └── UnitSettings.swift       — Préférences unités (kg/lbs)
│
└── Views/
    ├── Dashboard/               — Accueil, MorningBrief, PeakPrediction, Ghost
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
├── index.py              — Routes Flask + entry point Vercel
├── db.py                 — Couche données Supabase (toutes les tables)
├── progression.py        — Algorithme 1RM, progression de charges, RIR/RPE
├── deload.py             — Détection stagnation, RPE fatigue, chute 1RM
├── sessions.py           — Log et récupération séances
├── planner.py            — Programme hebdomadaire
├── inventory.py          — Exercices et inventaire
├── acwr.py               — Acute:Chronic Workload Ratio
├── life_stress_engine.py — Life Stress Score (LSS)
├── wearable.py           — Sync Apple Watch → Supabase
├── nutrition.py          — Journal alimentaire
├── body_weight.py        — Suivi poids corporel
├── morning_brief.py      — Brief matinal IA
└── …                     — sleep, mood, journal, goals, hiit, cardio, etc.
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

## Coach IA (`IntelligenceView` + `api/index.py`)

- Propositions séance : `POST /api/ai/propose`
- Insights : `POST /api/ai/insights`
- Narrative semaine : `POST /api/ai/narrative` (cachée par clé `narrative_YYYY-WXX`)
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
