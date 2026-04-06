# État du projet — TrainingOS

Dernière mise à jour : 2026-04-06

---

## Architecture actuelle

**App iOS native SwiftUI** connectée à un **backend Flask/Vercel** + **Supabase**.
La version PWA/Capacitor a été abandonnée au profit d'une app Swift pure.

---

## Systèmes complétés

### Smart Progression (coaching post-séance)
- Classification exercices : `load_profile` (compound_heavy/hypertrophy/isolation/NULL) + `category` (push/pull/legs/core) sur tous les exercices de la table `exercises`
- `api/smart_progression.py` : moteur de suggestions — compare session courante vs précédente du même `session_name` (Push A vs Push A, etc.)
- Règles par profil : compound_heavy/hypertrophy → ≥90% working sets at top_reps → +weight; isolation → 100%
- Wave loading : seuls les sets au poids max évalués (working sets)
- Plateau ≥3 sessions : cycle add_set (max 4 sets) → deload −10%
- Anti-régression : max_weight < précédent → flag regression
- Fatigue globale : ≥50% regressions → fatigue_warning sur toutes les suggestions
- `GET /api/progression_suggestions?date&session_type&session_name` → liste de suggestions
- `POST /api/apply_progression` → update default_scheme + weights KV
- iOS : `ProgressionSuggestionsSheet.swift` (sheet post-séance avec sections COACHING/MAINTENIR, Appliquer/Ignorer, toolbar Passer→Terminer)
- iOS : `Models/ProgressionSuggestion.swift` (struct Codable)
- `workout_sessions.session_name TEXT` : colonne stockant "Push A", "Pull B", etc. pour le matching précis (migration 010)

### Core entraînement
- Logging séances musculaires (exercices, séries, poids, RPE, RIR)
- Progression automatique des charges (1RM Epley, algorithme RPE gradué 5 niveaux)
- Déload automatique (détection stagnation + fatigue RPE + chute de performance) + bouton "Appliquer le déload (−15%)"
- Séances HIIT avec timer dédié (beeps, flash, presets, notifications background)
- Séance du soir (second slot quotidien) — pipeline complet
- Historique séances muscu + HIIT avec édition et pagination (limit/offset)
- Programme hebdomadaire (planificateur par jour, placeholder si séance vide)
- Inventaire des exercices (CRUD complet, temps de repos, tracking type)
- Type EZ-Bar : poids total direct (pas de multiplication), champ "poids barre EZ", couleur jaune

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
- Historique conversations persisté (`@AppStorage`, Codable `ChatMessage`)

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
- `CardInfoButton` + `InfoSheetView` : bouton ⓘ contextuel sur les cards LSS, déload, prévision 7j, volume landmarks (MEV/MAV/MRV)
- `ProactiveBannerCard` : bannière dismissable en tête du Dashboard pour les alertes proactives

### Santé & récupération
- Recovery modifiable (LogRecoverySheet avec prefillEntry, FAB adaptatif)
- Nutrition : édition d'entrée (EditNutritionSheet, endpoint /api/nutrition/edit)
- Apple Watch sync (HealthKit → Supabase via WatchSyncService)
- Life Stress Score (LSS) : 5 composantes (sommeil, HRV, FC repos, stress, fatigue)
- ACWR (Acute:Chronic Workload Ratio)
- RecoveryView, BodyCompView, CardioView, SleepView
- SleepView : bridge `recovery_log → sleep` quand `sleep_records` vide (fallback HealthKit, `source: "healthkit"`, `bedtime: "—"`, `quality: 0`)
- MentalHealth suite (mood, journal, breathwork, PSS, self-care)
- HealthDashboard agrégé

### Objectifs
- CRUD objectifs exercice avec deadline
- Animation achievement (sparkles + scale spring)
- Notifications locales J-7 et J-1 avant deadline
- **Smart Goals** (2026-04-05) : 7 objectifs calculés automatiquement (% masse grasse, masse maigre, tour de taille, volume hebdo, séances/semaine, protéines/jour, streak nutrition)
  - Table Supabase `smart_goals` (id, type, target_value, initial_value, target_date, created_at)
  - `GET /api/smart_goals` — calcule `current_value` + `progress` en temps réel
  - `POST /api/smart_goals/save` — capture `initial_value` automatiquement à la création
  - `POST /api/smart_goals/delete`
  - iOS : section "SANTÉ & PERFORMANCE" dans ObjectifsView, `SmartGoalCard`, `AddGoalSheet` avec picker segmenté "Santé / Perf | Exercice"

### Feedback proactif (`api/alerts.py` + `AlertService.swift`)
- 5 détecteurs read-only : protéines basses 2j, calories insuffisantes 2j, aucun log après 18h, même groupe musculaire 2j consécutifs, RPE > 8.5 sur 3 séances
- `GET /api/proactive_alerts` → liste d'alertes triées par priorité
- `AlertService` singleton : fetch au foreground + après log nutrition, dismiss par jour via UserDefaults
- Notification locale schedulée à 19h30 si alerte présente et heure non passée

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
| Smart progression post-séance (per-exercise coaching) | ✅ (2026-03-31) | `smart_progression.py` |

---

## Migrations en attente

| Migration | Fichier | Statut |
|---|---|---|
| 003_session_type | `docs/migrations/003_session_type.sql` | ✅ Appliquée (2026-03-29) |
| 004_food_catalog | `docs/migrations/004_food_catalog.sql` | ✅ Appliquée (2026-03-30) |
| 005_nutrition_intel | `docs/migrations/005_nutrition_intel.sql` | ✅ Appliquée (2026-03-30) |
| 006_load_profile | `docs/migrations/006_load_profile.sql` | ✅ Appliquée (2026-03-31) |
| 007_exercise_classification_1 | `docs/migrations/007_exercise_classification_1.sql` | ✅ Appliquée (2026-03-31) |
| 008_exercise_classification_2 | `docs/migrations/008_exercise_classification_2.sql` | ✅ Appliquée (2026-03-31) |
| 009_fix_categories_2 | `docs/migrations/009_fix_categories_2.sql` | ✅ Appliquée (2026-03-31) |
| 010_session_name | `docs/migrations/010_session_name.sql` | ✅ Appliquée (2026-04-04) |
| 011_kv_migration | `docs/migrations/011_kv_migration.sql` | ✅ Appliquée + table kv supprimée (2026-04-04) |

---

## En cours / Prochaines étapes

1. **Rebuild iOS Xcode** : compiler tous les changements 2026-04-06 (composants UI, timezone, cache fix)
2. Tests E2E iOS (XCUITest flows critiques)
3. Heatmap HIIT distinct de muscu dans StatsView
4. Remplir le profil utilisateur (name, age, height, etc.)
5. Configurer les cibles macro glucides/lipides dans NutritionView
6. Smart Goals — prochains types : 1RM estimé, pace cardio, distance mensuelle, FC repos, PSS, streak sommeil
7. `ErrorBannerView` à intégrer dans les views qui fetchent (actuellement créé mais non utilisé)

## Complété récemment (2026-04-06)

- **Composants UI partagés** : 4 composants dans `Views/Components/` ajoutés au projet Xcode :
  - `AppLoadingView` — spinner standardisé orange (9 fichiers migrés)
  - `EmptyStateView(icon:title:subtitle:action:)` — état vide réutilisable (RecoveryView, CardioView, NutritionView)
  - `ToastView` + `.toast()` modifier — feedback toast 2.5s auto-dismiss (HistoriqueView, CardioView, RecoveryView, NutritionView, ObjectifsView)
  - `ErrorBannerView(error:onRetry:onDismiss:)` — bannière erreur réseau réutilisable
- **Timezone fix global** : `DateFormatter.isoDate` a maintenant `timeZone = America/Montreal`. `DashboardView.todayStr` et `RecoveryView.todayStr` utilisent le singleton (suppression instances locales).
- **Cache invalidation** : `deleteCardio` invalide `cardio_history` + `stats_cardio` après suppression.
- **LazyVStack** : `HistoriqueView` — `VStack` → `LazyVStack` pour les 3 listes (muscu, HIIT, timeline).
- **Toast feedback destructif** : toasts de confirmation après suppression dans 5 views principales.

## Complété récemment (2026-04-05)

- **15 UX friction fixes** : labels slider mood, haptic/beep fin timer, notif PSS hebdo, presets deadline objectifs, delta badge progression, haptics breathwork, bouton "Sauter" exercice, skeleton inventaire, quantity inline nutrition
- **Dashboard volume total** : enrichissement depuis `v_session_volume` dans `api_dashboard()`
- **Body comp toujours en lbs** : 13 remplacements UnitSettings → formatters directs lbs dans BodyCompView
- **Data body comp Styku** : 2 entrées mises à jour (poids + 5 mensurations calculées depuis deltas PDF) ; poids DB convertis kg→lbs (189.3 / 179.3)
- **Fix `/api/set_goal`** : lisait `"weight"` mais iOS envoyait `"goal_weight"` → goals jamais sauvegardés
- **Profil poids** : mis à jour à 179.3 lbs (dernier scan Styku mars 2026)
- **Smart Goals** : table `smart_goals` Supabase (+ RLS), 3 endpoints backend, 7 types calculés en temps réel, iOS complet (`SmartGoalCard`, `AddGoalSheet` dual-mode, `SmartGoalEntry` model + extension)

## Complété récemment (2026-04-04)

- **Migration KV → relational** : migration 011 appliquée, table `kv` supprimée. Toutes les données dans tables relationnelles (mood_logs, habits, coach_messages, pss_records, sleep_records, goals_archived, breathwork_sessions).
- **Fix `inventory_types` nulls** : `info.get("type") or "machine"` remplace `info.get("type", "machine")` — évite les nulls qui cassaient le décode Swift `[String: String]` (4 emplacements dans index.py).
- **Fix smallint RPE** : `int(round(float(rpe)))` dans `db.create_workout_session` — float Python rejeté par colonne PostgreSQL `smallint`. Causait échec silencieux de toutes les créations de séances.
- **Fix `/api/ai/coach/history`** : `import db as _db` manquant → NameError 500. Corrigé.
- **Fix `SpecialSeanceView.alreadyLoggedToday`** : cross-check server state pour éviter le stale `@AppStorage` qui bloquait le re-log après échec réseau (iOS, rebuild requis).
- **Fix tendance body_weight** : 3 entrées lbs (180/176/188.6) converties en kg en DB. `get_tendance()` filtre >150 comme garde-fou. Tendance correcte : `↓ -5.1 kg`.
- **Nettoyage DB cardio** : 14 doublons supprimés (artefact migration KV, logged_at identique). 5 entrées uniques conservées.
- **Nettoyage DB breathwork** : session fantôme (0 min, 0 cycles) supprimée.
- **SleepView bridge HealthKit** : `sleep.py` bridgée sur `recovery_log` quand `sleep_records` vide. 15 entrées visibles dans SleepView (7.1h aujourd'hui). Fix timezone `ZoneInfo("America/Montreal")` pour `sleep/today`.
- **Audit complet runtime** : tous les ~75 endpoints testés en prod, rapport livré par écran.

## Complété récemment (2026-03-31)

- **Smart Progression Engine** : `api/smart_progression.py` — coaching post-séance per-exercise (increase_weight, increase_sets, deload, maintain, regression, fatigue_warning)
- **Classification exercices** : `load_profile` + `category` sur tous les exercices (migrations 006–009)
- **session_name matching** : colonne `workout_sessions.session_name` (migration 010) pour comparer Push A vs Push A, pas morning vs morning
- **iOS ProgressionSuggestionsSheet** : sheet post-séance avec Appliquer/Ignorer par exercice, toolbar Passer→Terminer
- **Suite de tests** : `tests/test_progression.py` (69 tests)
- **Nouveaux fichiers iOS** : `Models/ProgressionSuggestion.swift`, `Views/Seance/ProgressionSuggestionsSheet.swift`
- **Nouveaux fichiers Python** : `api/smart_progression.py`

## Complété récemment (2026-03-30)

- **RPE bonus session fix** : `int(rpe)` → `round(float(rpe), 1)` dans `db.create_workout_session`
- **Ez-bar** : nouveau type d'équipement (poids total, pas par côté), champ bar_weight, couleur jaune
- **CardInfoButton** : bouton ⓘ sur cards LSS/Coach du matin, Prévision 7j, Déload, Volume Landmarks
- **Système d'alertes proactives** : `api/alerts.py` + `AlertService.swift` + `ProactiveBannerCard` + notification 19h30
- **Nutrition intelligence** : settings glucides/lipides, DailyRemainingCard, AdherenceScoreCard, WorkoutBonusBadge, meal_type sur entrées
- **Migrations** : 004_food_catalog, 005_nutrition_intel appliquées

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
- Profil utilisateur vide (name, age, height, etc. — non saisi)
- `sleep_records` vide : SleepView affiche des données HealthKit bridgées sans bedtime/wake_time/quality

---

## Branches

| Branche | Statut |
|---|---|
| `master` | Branche principale / production |
