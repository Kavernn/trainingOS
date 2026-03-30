# État du projet — TrainingOS

Dernière mise à jour : 2026-03-29

---

## Architecture actuelle

**App iOS native SwiftUI** connectée à un **backend Flask/Vercel** + **Supabase**.
La version PWA/Capacitor a été abandonnée au profit d'une app Swift pure.

---

## Systèmes complétés

### Core entraînement
- Logging séances musculaires (exercices, séries, poids, RPE, RIR)
- Progression automatique des charges (1RM Epley, algorithme RPE gradué 5 niveaux)
- Déload automatique (détection stagnation + fatigue RPE + chute de performance) + bouton "Appliquer le déload (−15%)"
- Séances HIIT avec timer dédié (beeps, flash, presets, notifications background)
- Séance du soir (second slot quotidien) — pipeline complet, migration Supabase en attente
- Historique séances muscu + HIIT avec édition et pagination (limit/offset)
- Programme hebdomadaire (planificateur par jour, placeholder si séance vide)
- Inventaire des exercices (CRUD complet, temps de repos, tracking type)

### Statistiques & progression
- StatsView 5 onglets : Volume / 1RM / Groupes musculaires / Cardio / Corps
- Period picker (7j / 30j / 90j / tout)
- Smart Insights (texte narratif auto-généré)
- Personal Records (PR detection + notification locale)
- Sparklines et graphiques Charts

### Coach IA (IntelligenceView)
- Propositions de séance (Claude Sonnet 4.6)
- Insights hebdomadaires
- Récit narratif de la semaine (NarrativeCard, cache par semaine ISO)
- Contexte athlete enrichi : LSS, ACWR, poids, groupes musculaires, sessions (~1400 chars terse)

### Dashboard & UX
- TodayCard en position #1 (action principale en haut de page)
- Skeleton loading animé (`DashboardSkeletonView` + `SkeletonBar`)
- Cards tappables : RecoverySnapshot → RecoveryView, StatsRow → StatsView, NutritionSummary → NutritionView
- MorningBrief enrichi : LSS sparkline 7j, readiness delta, lien "Compléter →" si données partielles
- PeakPredictionCard avec CTA "Jour optimal : X → Voir les stats"
- DeloadChipView (niveau 1 compact) vs DeloadBannerView (niveau 2 complet)
- MoodCardView (card proper avec icône + titre)
- GreatDayCard intégré comme badge "Parfait ⭐" dans TodayCardView
- Ghost Mode (SeanceView) : bannière meilleure session + barre progression volume
- Haptics sur toutes les actions importantes
- Confetti sur PR et complétion de séance
- Timer de repos auto-start après chaque log

### Santé & récupération
- Recovery modifiable (LogRecoverySheet avec prefillEntry, FAB adaptatif)
- Nutrition : édition d'entrée (EditNutritionSheet, endpoint /api/nutrition/edit)
- Apple Watch sync (HealthKit → Supabase via WatchSyncService)
- Life Stress Score (LSS) : 5 composantes (sommeil, HRV, FC repos, stress, fatigue)
- ACWR (Acute:Chronic Workload Ratio)
- RecoveryView, BodyCompView, CardioView, SleepView
- MentalHealth suite (mood, journal, breathwork, PSS, self-care)
- HealthDashboard agrégé

### Objectifs
- CRUD objectifs avec deadline
- Animation achievement (sparkles + scale spring)
- Notifications locales J-7 et J-1 avant deadline

### Infrastructure
- Offline-first : SyncManager (SwiftData → retry queue) + Supabase
- CacheService avec TTL par endpoint (dashboard=5min, seance=5min, stats=15min, programme=1h, recovery/cardio=10min, nutrition=5min, profil=30min) via sidecar `.expiry`
- NetworkMonitor (NWPathMonitor)
- UnitSettings (kg/lbs, km/mi)
- Timer background : `UNUserNotificationCenter` planifie notifications par phase

---

## Progressive overload — état des algorithmes

| Algorithme | Statut | Fichier |
|---|---|---|
| Double progression (reps → poids) | ✅ | `progression.py` |
| RPE gradué (5 niveaux) | ✅ (2026-03-26) | `progression.py` |
| RIR capture + API | ✅ (2026-03-26) | `index.py`, `SeanceView.swift` |
| Trend analysis 4 semaines | ✅ (2026-03-26) | `progression.py` |
| Détection chute de performance (1RM) | ✅ (2026-03-26) | `deload.py` |
| Détection stagnation | ✅ | `deload.py` |
| Déload auto (stagnation + RPE + drop) | ✅ | `deload.py` |
| e1RM Epley | ✅ | `progression.py` |

---

## Migrations en attente

| Migration | Fichier | Statut |
|---|---|---|
| 003_session_type | `docs/migrations/003_session_type.sql` | ✅ Appliquée (2026-03-29) |

---

## En cours / Prochaines étapes

1. Tests E2E iOS (XCUITest flows critiques)
2. Heatmap HIIT distinct de muscu dans StatsView

## Complété récemment (2026-03-29) — Phase 2 todos

- Validation photo profil (500KB max, alert erreur)
- Export données CSV/JSON dans ProfileView (`/api/export_data`, ShareSheet)
- Badge "En programme" + filtre chip dans InventaireView
- HIIT templates favoris sauvegardables (`@AppStorage("hiit_templates")`)
- HealthKit auto-sync au lancement (`WatchSyncService.syncIfNeeded()`)
- Filtre par mois dans Historique (`MonthPickerSheet`, `?month=YYYY-MM`)
- Timeline tab dans Historique (muscu + HIIT merged par date)
- Archivage objectifs atteints (sections Active/Atteints/Archivés, `/api/archive_objectif`)
- Intelligence : historique conversations persisté (`@AppStorage`, Codable `ChatMessage`)
- Mood corrélation RPE : `MoodRPECorrelationCard` scatter + Pearson r
- Injury tracking : champ "zone douloureuse" dans `ExerciseCard`, `pain_zone` dans `/api/log`
- SeanceView mode set-by-set : toggle ➜ + bouton ✓ par set, auto-log au dernier set

---

## Dette technique connue

- `DEBUG` prints dans `db.py` — à remplacer par un vrai logger
- Pas de rate limiting sur les appels Claude (coût API non maîtrisé)
- `SECRET_KEY` avec valeur par défaut dans `index.py` — doit être forcé en prod
- Pas de tests E2E iOS (XCUITest)
- Pas de documentation Swagger/OpenAPI des routes backend

---

## Branches

| Branche | Statut |
|---|---|
| `master` | Branche principale / production |
