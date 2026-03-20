# TrainingOS — Native SwiftUI App

Application iOS native de tracking fitness/santé connectée à un backend Flask déployé sur Vercel + Supabase.

---

## Setup Xcode

1. Ouvrir `TrainingOS.xcodeproj`
2. Signer avec ton Apple Developer account (Signing & Capabilities)
3. Activer **HealthKit** dans les capabilities
4. Build & Run sur device physique (HealthKit ne fonctionne pas sur simulateur)

### Variables d'environnement (backend)

| Variable | Description |
|---|---|
| `SUPABASE_URL` | URL du projet Supabase |
| `SUPABASE_KEY` | Clé service role Supabase |
| `SECRET_KEY` | Clé Flask sessions |
| `ANTHROPIC_API_KEY` | Pour les routes IA (coach, planner) |
| `X_RAPIDAPI_KEY` | Optionnel — API nutrition externe |

---

## Architecture

```
trainingOS/
├── TrainingOSApp.swift          — Entry point, setup SyncManager + HK background delivery
├── ContentView.swift            — TabView navigation principale
│
├── Models/
│   └── APIModels.swift          — Tous les structs Codable (CardioEntry, RecoveryEntry,
│                                  WearableSnapshot, DashboardData, etc.)
│
├── Services/
│   ├── APIService.swift         — Couche réseau vers le backend Vercel (fetch + offlinePost)
│   ├── CacheService.swift       — Cache mémoire TTL pour les requêtes GET
│   ├── HealthKitService.swift   — Lecture Apple Health (steps, sleep, RHR, HRV,
│   │                              active energy, workouts, body composition)
│   ├── WatchSyncService.swift   — Orchestration auto-sync Watch → Supabase (30 min dedup,
│   │                              background delivery, isSyncing/lastSyncDate)
│   ├── NetworkMonitor.swift     — Détection offline (NWPathMonitor)
│   ├── SyncManager.swift        — File de mutations offline (SwiftData → retry)
│   ├── PendingMutation.swift    — Modèle SwiftData pour mutations en attente
│   └── UnitSettings.swift       — Préférences unités (kg/lbs, km/mi)
│
├── Views/
│   ├── SplashView.swift
│   ├── Dashboard/
│   │   ├── DashboardView.swift          — Accueil, cards résumé, sync Watch au foreground
│   │   └── ChecklistCardView.swift      — Checklist quotidienne
│   ├── Seance/
│   │   ├── SeanceView.swift             — Logging entraînement (exercices, séries, poids)
│   │   └── SeanceSoirView.swift         — Séance du soir
│   ├── Historique/
│   │   └── HistoriqueView.swift         — Historique des séances
│   ├── Recovery/
│   │   └── RecoveryView.swift           — Récupération (sommeil, FC repos, HRV, douleurs)
│   │                                      auto-sync Watch + badge HealthKit
│   ├── Cardio/
│   │   └── CardioView.swift             — Log cardio (course, vélo, natation, etc.)
│   ├── Sleep/
│   │   └── SleepView.swift              — Suivi sommeil détaillé
│   ├── BodyComp/
│   │   └── BodyCompView.swift           — Poids corporel et composition
│   ├── Nutrition/
│   │   └── NutritionView.swift          — Journal alimentaire et macros
│   ├── Stats/
│   │   └── StatsView.swift              — Graphiques progression et volume
│   ├── HIIT/
│   │   └── HIITHistoriqueView.swift     — Historique sessions HIIT
│   ├── Timer/
│   │   └── TimerView.swift              — Timer intervalles (natif, sans réseau)
│   ├── Intelligence/
│   │   └── IntelligenceView.swift       — Coach IA, analyse, recommandations (Claude)
│   ├── MentalHealth/
│   │   ├── MentalHealthView.swift
│   │   ├── MentalHealthDashboardView.swift
│   │   ├── MoodTrackerView.swift        — Suivi humeur quotidien
│   │   ├── JournalView.swift            — Journal de réflexion
│   │   ├── BreathworkView.swift         — Exercices de respiration guidés
│   │   ├── SelfCareView.swift           — Checklist self-care
│   │   └── CrisisResourcesView.swift
│   ├── HealthDashboard/
│   │   └── HealthDashboardView.swift    — Vue agrégée santé (HRV, sommeil, stress)
│   ├── Programme/
│   │   └── ProgrammeView.swift          — Visualisation programme d'entraînement
│   ├── Objectifs/
│   │   └── ObjectifsView.swift          — Suivi objectifs par exercice
│   ├── Inventaire/
│   │   └── InventaireView.swift         — Gestion exercices et charges
│   ├── PSS/
│   │   └── PSSView.swift                — Perceived Stress Scale
│   ├── XP/
│   │   └── XPView.swift                 — Système d'expérience / gamification
│   ├── Notes/
│   │   └── NotesView.swift              — Notes libres
│   ├── Profile/
│   │   └── ProfileView.swift            — Profil utilisateur et paramètres
│   └── More/
│       └── MoreView.swift               — Menu secondaire
│
├── Utilities/
│   ├── Extensions.swift         — Color(hex:), View modifiers, DateFormatter helpers
│   └── DesignSystem.swift       — Composants UI réutilisables (FAB, glassCard, etc.)
│
└── TrainingOS/
    └── Assets.xcassets          — AppIcon, SplashImage
```

---

## Backend (`api/`)

Flask déployé sur **Vercel** (serverless), base de données **Supabase** (PostgreSQL).
Fallback KV JSON local si Supabase indisponible.

```
api/
├── index.py              — Routes Flask principales + registration wearable
├── db.py                 — Couche données Supabase (toutes les tables)
├── wearable.py           — POST /api/wearable/sync (Apple Watch → Supabase)
├── planner.py            — Planification hebdomadaire, programme
├── blocks.py             — Blocs d'entraînement (force, HIIT, cardio)
├── sessions.py           — Log séances
├── weights.py            — Historique charges par exercice
├── progression.py        — Algorithme progression / 1RM
├── deload.py             — Détection et recommandation deload
├── volume.py             — Calcul volume (sets × reps × poids)
├── acwr.py               — Acute:Chronic Workload Ratio
├── nutrition.py          — Journal alimentaire
├── body_weight.py        — Log poids corporel
├── sleep.py              — Données sommeil
├── mood.py               — Tracker humeur
├── journal.py            — Journal de réflexion
├── mental_health_dashboard.py
├── pss.py                — Perceived Stress Scale
├── self_care.py          — Checklist self-care
├── breathwork.py         — Sessions respiration
├── life_stress_engine.py — Score stress agrégé
├── correlations.py       — Corrélations santé / performance
├── health_data.py        — Agrégation données santé
├── morning_brief.py      — Brief matinal IA
├── goals.py              — Objectifs par exercice
├── inventory.py          — Exercices et inventaire
├── hiit.py               — HIIT log
├── timer.py              — Presets timer
├── log_workout.py        — Log exercice individuel
├── user_profile.py       — Profil utilisateur
└── main.py / flask_app.py — Points d'entrée alternatifs
```

### Flow Apple Watch → Supabase

```
Apple Watch
  └── HealthKit (iPhone)
        └── HealthKitService.fetchTodayHealthSnapshot()
              └── WatchSyncService.sync()
                    └── APIService.syncWearableData()
                          └── POST /api/wearable/sync
                                ├── recovery_logs  (steps, sleep, RHR, HRV, active energy)
                                ├── cardio_logs    (workouts du jour)
                                └── body_weight_logs (poids + % gras si absent)
```

**Déclencheurs sync :**
| Trigger | Fréquence |
|---|---|
| App launch | 1× au démarrage |
| App foreground (`scenePhase == .active`) | Si > 5 min depuis dernier refresh |
| Background HealthKit observers | ~toutes les heures |
| Ouverture RecoveryView | Si > 30 min depuis dernière sync |
| Bouton refresh manuel (RecoveryView) | À la demande |

---

## Base de données (Supabase)

Schéma complet : `docs/schema.sql`
Migration Apple Watch : bloc `MIGRATION 001` en fin de fichier.

Tables principales :
`workout_sessions`, `exercise_logs`, `cardio_logs`, `recovery_logs`,
`body_weight_logs`, `nutrition_entries`, `mood_entries`, `journal_entries`,
`sleep_records`, `hiit_logs`, `pss_scores`, `life_stress_scores`

---

## Tests

```
TrainingOSTests/
├── APIModelsTests.swift
├── CacheServiceTests.swift
├── SeanceViewModelTests.swift
├── SyncManagerTests.swift
├── TestHelpers.swift
└── TrainingOSTests.swift
```

---

## Docs

```
docs/
├── ARCHITECTURE.md          — Décisions architecturales
├── DECISIONS.md             — ADRs (Architecture Decision Records)
├── STATE.md                 — État actuel du projet
├── DATA_INTEGRITY_AUDIT.md  — Audit intégrité données
├── schema.sql               — Schéma Supabase complet + migrations
└── migrations/              — Migrations SQL individuelles
```
