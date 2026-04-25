# État du projet — TrainingOS

Dernière mise à jour : 2026-04-25

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
- **Smart Goals** (2026-04-05) : 12 types total
  - Types originaux : body_fat, lean_mass, waist_cm, weekly_volume, training_frequency, protein_daily, nutrition_streak
  - **Types avancés** (2026-04-06) : estimated_1rm (1RM estimé meilleur exo), monthly_distance (cardio km), resting_hr (FC repos), pss_avg (stress PSS moyen), sleep_streak (streak sommeil)
  - Table Supabase `smart_goals` (id, type, target_value, initial_value, target_date, created_at)
  - iOS : section "SANTÉ & PERFORMANCE" dans ObjectifsView, `SmartGoalCard`, `AddGoalSheet`

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
| RIR capture + API | ✅ (2026-03-26) | `routes/workout.py`, `SeanceView.swift` |
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
| 012_workout_sessions_completed | `docs/migrations/012_workout_sessions_completed.sql` | ✅ Appliquée (2026-04-16) + backfill rpe IS NOT NULL |
| 013_nutrition_scan | `docs/migrations/013_nutrition_scan.sql` | ✅ Appliquée |

---

## En cours / Prochaines étapes

1. **Supabase Storage** : créer le bucket `profile-photos` (public) pour activer upload photo → URL (le code est prêt, bucket absent).
2. **Cible UITest Xcode** : ajouter `TrainingOSUITests` comme nouvelle cible UITest dans le projet Xcode pour exécuter les 5 flows E2E.
3. **Vercel env var** : `TRAININGOS_API_KEY` déployé ✅ — auth active en prod.

## Complété récemment (2026-04-25 — Programme UL/PPL + Supersets)

### Nouveau programme d'entraînement : UL/PPL
- **5 sessions** créées dans Supabase : Upper A, Lower A, Push, Pull, Legs B
- **8 exercices par session** en 4 supersets (SS1–SS4), modèle double progression, incrément lbs (composés +5 lbs, isolation +2.5 lbs)
- **13 nouveaux exercices** créés avec champ `tips` (cue de coaching), par ex. Incline Dumbbell Curl, Single-Leg Press, Overhead Triceps Extension
- **21 exercices existants** enrichis avec `tips`
- **`weekly_schedule`** mis à jour : Lun→Upper A / Mar→Lower A / Mer→Push / Jeu→Pull / Ven→Legs B
- Ancien programme (Push A, Pull A, Legs, Push B, Pull B + Full Body) archivé — données historiques intactes

### Schema DB — colonnes supersets
- 3 colonnes ajoutées à `program_block_exercises` (migration appliquée en amont) :
  - `superset_group TEXT` (ex. "SS1"–"SS4", NULL = exercice solo)
  - `superset_position SMALLINT` (1=A, 2=B)
  - `rest_after_superset INT` (120 s sur toutes les B, NULL sur A et exercices solo)

### API — `GET /api/seance_data`
- **`inventory_hints`** : `{exerciceName: tip}` — construit depuis `exercises.tips` au moment de la réponse
- **`exercise_supersets`** : `{sessionName: {groupLabel: {A, B, rest}}}` — calculé par `db.get_session_supersets()`

### iOS — WorkoutModels.swift
- `SupersetEntry: Codable` (champs `a`, `b`, `rest` ; CodingKeys `"A"`, `"B"`, `"rest"`)
- `SeanceData` étendu : `inventoryHints: [String: String]` + `exerciseSupersets: [String: [String: SupersetEntry]]` (décodage avec `?? [:]` fallback)

### iOS — ExerciseCard.swift
- Propriété `hint: String? = nil` — affichée en italique gris dans la section expanded (sous les coaching chips)

### iOS — SeanceView / WorkoutSeanceView
- `@State inventoryHints` + `@State sessionSupersets` initialisés depuis `data` dans `loadInventory()`
- `onChange(data.inventoryHints)` pour maintenir l'état à jour
- `draggableCard` : passe `hint: inventoryHints[name]` à `ExerciseCard` ; paramètres `forceNoRest`/`restOverride` pour contrôler le timer par position superset
- `ExerciseRenderItem` enum (`.superset` / `.solo`) + `exerciseRenderItems` computed property — groupe les pairs A+B sans double-render
- `supersetBlock` : header capsule (label + "N s repos") → card A (pas de timer) → "↓ enchaîner" → card B (120 s timer)
- Fallback automatique au rendu plat quand `sessionSupersets` est vide (aucune régression sur les anciennes sessions)

---

## Complété récemment (2026-04-24)

### Audit séance log — 5 bugs critiques corrigés
- **`api/log` perf** : `load_weights()` → `load_weights([exercise], limit_per=10)` — chargeait tout l'historique à chaque appel
- **`api/log` fiabilité** : retourne HTTP 500 si `upsert_exercise_log_direct()` échoue (plus de `{"success": True}` silencieux)
- **`api/log_session` fiabilité** : retourne HTTP 500 si `complete_workout_session()` échoue
- **`SeanceSoirViewModel.finish()`** : ajout des appels `logExercise()` par exercice (manquants — seul `logSession()` était appelé)
- **`BonusSeanceViewModel.finish()`** : même fix — les exercices n'étaient pas loggés individuellement
- **"Reprendre la dernière séance"** : `ExerciseCard` redimensionne `evm.sets` au compte réel de `lastRepsParts` avant de remplir (plus de 4e set fantôme issu du `scheme` programme)

### Rebuild timer repos
- **`RestTimerManager` simplifié** : suppression de `pendingStart`, `confirmReplace`, `cancelReplace`, `requestAutoStart`, `restoreIfNeeded`, `syncFromEndDate`, `applyPreset`, `adjustTime`
- **Nouvelle API** : `start(seconds:exerciseName:)` — remplace toujours le timer en cours, auto-start immédiat · `resume()` · `dismiss()` · `isVisible` · `setPreset(_:)` · `adjust(by:)`
- **`FloatingRestTimerBar` redesigné** : carte flottante compacte (cornerRadius 22, background `#111128`, bordure colorée, shadow noire) — plus de barre pleine largeur étirée
- **Bouton dismiss (X)** ajouté sur la carte flottante
- **Suppression `RestTimerSheet`** (dead code — jamais présenté)
- **Suppression alert "Remplacer le timer ?"** (dialog irritante en pleine séance)
- `ExerciseCard.doLog()` → `start(seconds:exerciseName:)` (auto-start à chaque log)

---

## Complété récemment (2026-04-19 — Nouvelles features)

- **Body Composition Calculator (Navy formula)** : calculateur SwiftData complet. `BodyCompEntry` (`@Model` : date/weightLbs/bodyFatPct/fatMassLbs/leanMassLbs) ajouté au schema SwiftData dans `TrainingOSApp`. `NavyCalculatorView` : 4 steppers ±0.5/1 cm/lbs, formule Navy US (`495 / (1.0324 - 0.19077 * log10(waist-neck) + 0.15456 * log10(height)) - 450`), 3 result cards, barre de composition GeometryReader (vert lean / orange fat), badge catégorie (Athlète/Très fit/Fitness/Acceptable/Obèse), bouton Enregistrer → toast 2.5s. `BodyCompHistoryView` : `@Query` reverse, chart LineMark+AreaMark+PointMark % MG (Swift Charts), liste swipe-to-delete, empty state. Accessible depuis `MoreView` section "Corps & Santé". Tous les fichiers ajoutés au pbxproj manuellement (3× PBXBuildFile + PBXFileReference + group children + sources build phase).
- **Bilan IA post-séance** : `POST /api/ai/post_workout` dans `ai_coach.py` — récupère la session précédente du même type via `get_workout_sessions(limit=10)`, construit un contexte comparatif, appelle Claude Sonnet 4.6 (max_tokens=200, system prompt = 3 phrases exactes : évaluation/comparaison/recommandation), rate-limité via `_ai_rate_check()`. iOS : `fetchPostWorkoutBrief()` dans `APIService.swift` (POST avec sessionType/rpe/exos/comment/date). `AlreadyLoggedSeanceView` : `@State postWorkoutBrief` + `isLoadingBrief`, card purple "BILAN IA" affichée entre le récap et la preview demain, déclenchée à `.onAppear` (guarded contre double-fetch).
- **Streak counter** : déjà implémenté — `StreakBadge` dans `GreetingHeaderView` (calcul par arithmétique timestamp pure, pas Calendar.date(byAdding:) pour éviter crash iOS 26 0x8BADF00D). Affiché si streak > 1.
- **Volume par groupe musculaire** : déjà implémenté — `MuscleVolumeView` (performanceTab) + `MuscleBreakdownView` + `VolumeLandmarksCard` (vueGlobaleTab) dans `StatsView`, alimentés par `muscle_stats` + `muscle_landmarks` de `/api/stats_data`.

---

## Complété récemment (2026-04-19 — Bugs dashboard + UX + yoga/recovery)

- **Dashboard "Commencer la séance" stale (offline)** : root cause double — (1) `offlinePost` nil → cache dashboard non effacé → fetchDashboard servait l'ancien état ; (2) SyncManager.flushQueue rejoignait les mutations mais ne refreshait jamais le dashboard. Fix : `APIService.sessionLoggedToday` flag optimiste (set dès logSession, reset sur réponse serveur) ; TodayCardView observe ce flag ; SyncManager clear cache + fetchDashboard après toute mutation session rejouée.
- **Scan nutrition — caméra directe** : suppression de la `confirmationDialog` "Caméra / Bibliothèque photos". Le bouton scan ouvre maintenant directement `ImagePickerView(sourceType: .camera)`. Variables `showSourceChoice` et `showLibraryPicker` supprimées de `NutritionScanSheet`.
- **Suppression web app** : templates HTML Jinja2 (18 fichiers), static/, www/ (Capacitor), mobile/ (Capacitor iOS), capacitor.config.ts, package.json supprimés. `api/routes/data_views.py` allégé de 18 routes HTML → JSON uniquement. `api/index.py` nettoyé (pas de webbrowser.open, pas de TEMPLATES/STATIC). App = iOS + Mac Catalyst uniquement.
- **Yoga/Recovery ne s'enregistrent pas** : deux causes racines réglées. (1) Serveur : `api_seance_data()` utilisait `load_sessions()` (dict keyed by date) — si une session evening existait pour le même jour, elle écrasait la session morning yoga dans le dict → `already_logged = false` faux-négatif. Fix : `_db.get_workout_session(today_date)` direct (requête `session_type='morning'` uniquement). (2) iOS : `SpecialSeanceView.logSession()` utilisait `try?` qui swallowait toutes les erreurs et affichait toujours "Séance enregistrée ✅". Fix : `try/catch` + vérification `fresh.alreadyLogged` avant de confirmer le succès, alert erreur si non confirmé (même pattern que `SeanceViewModel.finish()`).

---

## Complété récemment (2026-04-16/17 — Bugs récupération, historique, dashboard)

- **Migration 012 appliquée** : `completed BOOLEAN DEFAULT FALSE` ajoutée à `workout_sessions` + backfill `SET completed=TRUE WHERE rpe IS NOT NULL`
- **Détection séance terminée** : triple check robuste (`completed OR rpe IS NOT NULL OR exercices loggués`) dans `api_dashboard()` et `api_seance_data()`
- **TodayCard 3 états** restaurés : "Commencer la séance" / "Continuer la séance" / carte verte "Complété" — basé sur `hasPartialLogs` + `isLoggedToday`
- **WeekProgressStripView** : compte aujourd'hui via `dash.alreadyLoggedToday` en fallback quand le dict `sessions` n'est pas encore mis à jour
- **Plank** ajouté dans l'inventaire des exercices
- **Recovery — steps ne se sauvegardaient pas** : deux bugs corrigés :
  1. iOS : `stepsStr.isEmpty ? nil : Int(stepsStr)` — champ vide envoyait `steps=0` écrasant les pas HK existants
  2. Serveur : `soreness=0 → NULL` — la CHECK constraint `soreness BETWEEN 1 AND 10` faisait échouer silencieusement tout l'upsert quand soreness=0 (défaut du slider)
- **Recovery — erreur upsert surfacée** : `api_log_recovery` retourne maintenant HTTP 500 si `upsert_recovery_log` échoue (au lieu de `{"ok": true}` silencieux)
- **Historique — double entrée bonus** : les sessions bonus sont fusionnées dans la session morning du même jour dans `api_historique_data` — RPE/comment hérités du bonus, exercices de la morning → une seule entrée par jour

## Complété récemment (2026-04-06 — A1 auth + UX Dashboard + UX Nutrition)

- **#A1 — Auth API** : `before_request` Flask vérifie `Authorization: Bearer <key>` sur les 124 routes (401 si absent). `URLSession.authed` côté iOS (extension dans `APIService.swift`) — 34 call sites couverts. Clé deployée sur Vercel.
- **UX Dashboard** — 5 frictions fixées :
  - `ReadinessStripView` (Whoop/Oura pattern) avant TodayCard
  - `ChecklistCardView` déplacée en sheet derrière bouton checklist dans le header
  - `MorningBriefCompactView` : toujours affiché (compact vert quand "go")
  - `WeekProgressStripView` sous TodayCard
  - `NutritionStripView` compact en position 4
  - Header : "VINCE SEVEN" retiré, `S7` → `Sem. 7`
- **UX Nutrition** — 5 frictions fixées :
  - `GroupedEntryList` : aliments groupés par repas avec subtotals kcal+prot
  - Journal en haut du scroll, graphes en bas
  - `WeeklyNutritionChart` fusionné (Calories/Protéines toggle, barres tappables avec détail)
  - Recherche texte dans `AddNutritionSheet` + "Manuel" visible dans header
  - "Recalculer" toujours visible dans Settings (plus conditionnel)

## Complété récemment (2026-04-06 — Audit complet items restants)

- **#A17** — `get_current_week()` lit `user_profile.created_at` depuis Supabase (fallback `2026-03-03`)
- **#A18** — `#Preview` ajouté dans StatsView, DashboardView, NutritionView, ObjectifsView, ProfileView
- **#A19** — `api/update_profile_photo` tente upload vers Supabase Storage (`profile-photos` bucket) → stocke `photo_url`. ProfileView utilise `AsyncImage`. Fallback base64 si bucket absent.
- **#A20** — Rate limiting IA migré vers table Supabase `ai_rate_limit` (hour_key TEXT PK, count INT) — cross-worker safe, `threading.Lock` retiré
- **Smart Goals types avancés** — 5 nouveaux types : `estimated_1rm`, `monthly_distance`, `resting_hr`, `pss_avg`, `sleep_streak` (backend `db.py` + iOS `SmartGoalOption`)
- **Profile non rempli** — Banner orange dans `ProfileView` quand champs essentiels absents. Tap → `EditProfileSheet`.
- **Nutrition macros** — Bouton "Calculer auto" dans `NutritionSettingsSheet` (split 30/45/25 P/G/L depuis kcal)
- **API README** — `api/README.md` : ~60 endpoints documentés, 8 blueprints, méthodes/params/notes
- **E2E UITests** — `TrainingOSUITests/TrainingOSUITests.swift` : 5 flows XCUITest (dashboard, log exo, finish session, nutrition, profil)
- **Keyboard dismiss** — `scrollDismissesKeyboard(.interactively)` ajouté à `IntelligenceView` chat scroll
- **Heatmap** — Confirmé déjà implémenté avec SessionHeatmapView (orange/bleu/violet)

## Complété récemment (2026-04-06 — Workout UX + tests de régression)

- **15 frictions workout UX corrigées** (`ExerciseCard.swift` + `SeanceView.swift`) :
  - RPE chips élargies 6-10 → 1-10 (ScrollView horizontal)
  - RIR header : sous-titre "avant échec" ajouté
  - Toggle set-by-set : label "Set à set" visible (plus icon seul)
  - "Reprendre la dernière séance" monté en première position dans la card
  - Bouton log : label "Logger" toujours visible
  - Historique : 3 sessions visibles par défaut (était 1)
  - "Sauter" : `confirmationDialog` avant de skipper l'exercice
  - `EnergyPreWorkoutSheet` : demande l'énergie **avant** la séance (1×/jour), plus dans FinishSessionSheet
  - `FinishSessionSheet` : énergie pré-remplie en lecture seule si déjà saisie au départ
  - Analyse IA post-séance : auto-déclenchée à l'ouverture (plus besoin de taper le bouton)
  - Haptic `.success` au commit de séance
- **B1 — `session_name` perdu sur CREATE** : `create_workout_session()` accepte maintenant `session_name` ; `log_session()` le propage — données non perdues sur les premières sessions du jour
- **B2 — Route `/api/progression_suggestions` inexistante** : route ajoutée dans `routes/workout.py`, appelle `smart_progression.generate_suggestions()` — `ProgressionSuggestionsSheet` fonctionne désormais pré- et post-séance
- **B3 — Schema doc stale** : `session_name TEXT` ajouté à `workout_sessions` dans `docs/schema.sql`
- **B4 — Race condition EnergyPreSheet / ProgressionSheet** : si energy sheet va s'afficher, progression check différé à `onChange(showEnergyPreSheet=false)` — les deux sheets ne se disputent plus le slot de présentation

## Complété récemment (2026-04-06 — Audit A2–A16)

- **A2 — Flask Blueprints** : `index.py` 3 071 lignes → ~100 lignes d'app factory. 8 blueprints dans `api/routes/` (profile, nutrition, ai_coach, goals, analytics, workout, data_views, wellness) + `api/utils.py` (helpers partagés : timezone, rate limiter, muscle analytics).
- **A4 — ExerciseViewModel** : extrait dans `Views/Seance/ExerciseViewModel.swift` (~880 lignes). `ExerciseCard` + `ExerciseLogResult` supprimés de `SeanceView.swift`.
- **A5 — AppState** : `Services/AppState.swift` — singleton `@MainActor ObservableObject` avec `api`, `alerts`, `units`, `userProfile`, `todayStr`. Injecté via `.environmentObject` dans `TrainingOSApp`. Connecté à Dashboard, Nutrition, Objectifs, Recovery, Cardio.
- **A8 — ErrorBannerView** : intégré dans DashboardView, NutritionView, ObjectifsView (via `networkError: String?` + retry handler).
- **A12 — ViewModels** : `DashboardViewModel` + `NutritionViewModel` extraits. 9 `@State` retirés de DashboardView, 6 de NutritionView.
- **A14 — Codable NutritionView** : `NutritionEntry`, `NutritionSettings`, `NutritionTotals`, `NutritionDayHistory` tous `Decodable`. `NutritionDataResponse` top-level. `AnyCodingKey` pour fallbacks de clés (nom/name, heure/time). JSONDecoder 3 lignes dans NutritionViewModel.
- **A15 — Split APIModels.swift** : 1 252 lignes → 6 fichiers domaine (`WorkoutModels`, `NutritionModels`, `WellnessModels`, `GoalsModels`, `AnalyticsModels`, `ProfileModels`). `APIModels.swift` ne garde que `PagedResponse<T>` + `SafeString`.
- **A16 — Annotations unités** : `-- unit: lbs` dans `docs/schema.sql`, `# unit: lbs (not kg)` dans `db.py` (`get_body_weight_logs`, `upsert_body_weight`).

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
- Pas de tests E2E iOS (XCUITest cible non ajoutée dans Xcode)
- Pas de documentation Swagger/OpenAPI des routes backend
- `sleep_records` vide : SleepView affiche des données HealthKit bridgées sans bedtime/wake_time/quality
- Supabase Storage bucket `profile-photos` non créé (upload photo profil → fallback base64)

---

## Branches

| Branche | Statut |
|---|---|
| `master` | Branche principale / production |
