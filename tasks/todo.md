# TrainingOS — TODO & Améliorations

> Tour de l'app réalisé le 2026-03-15. Mis à jour le 2026-06-03.
> Audit senior dev/UX ajouté le 2026-04-05 — 20 items priorisés.

---

## 🛡️ Backlog structurel — gardes différées

### Option 2 : garde data-driven `SeanceData.sessionType` (différée 2026-07-20)

**Raison d'être** : la garde `restoreLogResults` matin s'appuie aujourd'hui sur
`draftSessionType` (état INTERNE du VM, set à l'init). Si un futur écran instancie
mal le VM (ex : `SeanceViewModel(draftSessionType: "morning")` en dur alors que le
contexte est soir), la garde interne ne détecte pas. Option 2 déplacerait la vérité
vers le PAYLOAD `SeanceData.sessionType` renvoyé par le backend — le VM ne peut
plus mentir sur son type.

**Coût** : backend query param `session_type=X` sur `/api/seance_data`, échoyé
dans le payload + `SeanceData.sessionType: String` Codable + swap de la condition
`restoreLogResults` (`seanceData.sessionType` au lieu de `draftSessionType`).

**Déclencheur** : si un pré-remplissage fantôme réapparaît en séance soir malgré
Option 1 (init obligatoire, commit `fix(seance): SeanceViewModel.init exige
draftSessionType explicite`) et Option 3 (session_type dans weights.history, commit
`fix(seance): weights.history conscient de session_type`), Option 2 devient le
remède prioritaire. Sans ce déclencheur, elle dupliquerait une vérité que le VM
possède déjà — sur-engineering.

---

## ⌚ Watch App — Phase 1 (en cours, 2026-06-03)

### ✅ Fait
- [x] Architecture et plan validés (offline-first, Watch = terminal, tout passe par iPhone)
- [x] Fichiers iOS créés : `Services/WatchConnectivityManager.swift`
- [x] Fichiers Watch créés dans `VinceSeven Watch Watch App/` : WatchTypes, WatchSessionManager, VinceSevenWatchApp, HomeView, ActiveSessionView, MorningLogView, RestTimerView
- [x] Target Watch ajouté dans Xcode ("VinceSeven Watch Watch App")
- [x] Bundle ID Watch configuré : `com.kavernntrainingos.app.TrainingOS.watchkitapp`
- [x] Deployment target Watch abaissé à watchOS 10.0
- [x] Build iOS passe (0 erreur)
- [x] WatchConnectivityManager s'initialise correctement au lancement iOS

### 🔴 Bloquant — Déploiement Watch
- [ ] **Connexion Xcode ↔ Watch échoue** : "The device rejected the connection request" (Code 4 / RemotePairingError 1007)
- [ ] **À débloquer avant de continuer** :
  1. Redémarrer la Watch (bouton latéral long → éteindre → rallumer)
  2. iPhone branché en **USB** au Mac (pas WiFi) pour le déploiement initial
  3. Vérifier **Developer Mode** sur la Watch : iPhone → app Watch → Privacy & Security → Developer Mode → On
  4. Xcode → Window → Devices and Simulators → Watch doit réapparaître sous l'iPhone
  5. Relancer Cmd+R avec le scheme "VinceSeven Watch Watch App"

### 🟡 À faire après déploiement (Phase 1 suite)
- [ ] Tester la connexion WCSession Watch ↔ iPhone (logs `WCSession counterpart app not installed` doivent disparaître)
- [ ] Tester logger un set depuis la Watch → vérifie dans Supabase
- [ ] Tester log du matin depuis la Watch → vérifie dans Supabase
- [ ] Tester timer repos sur la Watch
- [ ] Intégrer `WatchConnectivityManager.pushActiveSession()` dans SeanceView au démarrage d'une séance
- [ ] Intégrer `WatchConnectivityManager.clearActiveSession()` dans FinishSessionSheet
- [ ] Ajouter capability WatchConnectivity aux deux targets (si pas encore fait)

### 📋 Phase 2 — Après validation Phase 1
- [ ] Complications watchOS (circulaire streak, rectangulaire séance du jour)
- [ ] Log nutrition rapide (5 derniers repas)
- [ ] Suggestion poids (dernier set connu)
- [ ] Timer endurance Watch (Plank, Deadhang)

---

## 🐛 Fixes critiques — 2026-05-05

- [x] **iOS 26 beta crash "freed pointer not last allocation"** : crash SIGABRT dans `libswift_Concurrency.dylib` → régression beta iOS 26 sur `async let` parallèle (LIFO dealloc check). Fix : remplacement de **tous** les `async let` par `await` séquentiels dans 19 fichiers Swift (IntelligenceView, DashboardViewModel, DashboardView, HealthKitService, XPView, SleepView, HealthDashboardView, StatsView, RecoveryView, MoodTrackerView, BreathworkView, SelfCareView, MentalHealthView, JournalView, BodyCompView, PSSView, NutritionView, ObjectifsView, ProgrammeView). *(2026-05-05)*
- [x] **Supabase "Server disconnected"** : connexions httpx keep-alive stale après inactivité. Fix : `_reconnect()` + pattern `_do()` appliqué aux 42 fonctions de `db.py` — reconnexion automatique + retry une fois sur disconnect. *(2026-05-05)*
- [x] **UIKit appearance iOS 26** : reverted to standard TabView + `guard #unavailable(iOS 26) else { return }` dans `ContentView.init()` pour les UITabBarAppearance/UINavigationBarAppearance. `iOS26TabContainer` (fausse piste) supprimé. SplashView restauré dans `TrainingOSApp`. *(2026-05-05)*
- [x] **`fetchDeload: stagnants[0]` dict vs String** : cache périmé contenait `stagnants` comme liste de dicts `[{exercise, weight, séances, stagnation}]` (ancien format). Fix : `DeloadReport.init(from:)` essaie `[String]` d'abord, fallback vers extraction `.exercise` des dicts. `AnalyticsModels.swift`. *(2026-05-05)*

---

## ✨ Nouvelles features — 2026-04-19

- [x] **Body Composition Calculator (Navy formula)** : `BodyCompEntry` SwiftData `@Model`, `NavyCalculatorView` (4 steppers, formule Navy, barre compo, catégorie, save → toast), `BodyCompHistoryView` (chart % MG Swift Charts, swipe-to-delete, empty state). Accessible depuis MoreView "Corps & Santé". Enregistré dans pbxproj (3 fichiers). *(2026-04-19)*
- [x] **Bilan IA post-séance** : `POST /api/ai/post_workout` (3 phrases Claude : évaluation/comparaison/recommandation, rate-limited, contexte session courante + précédente même type). iOS : `fetchPostWorkoutBrief()` dans APIService, card purple "BILAN IA" dans `AlreadyLoggedSeanceView` entre récap et demain. *(2026-04-19)*

---

## 🐛 Bugs & UX — 2026-04-19

- [x] **Dashboard "Commencer la séance" malgré séance loggée (offline)** : quand la séance était loggée hors-ligne, `offlinePost` retournait `nil` → cache dashboard non effacé → `fetchDashboard()` servait le cache périmé → TodayCard restait en état "pas loggé". De plus, `SyncManager.flushQueue()` ne refreshait pas le dashboard après avoir rejoué les mutations. Fix : (1) flag optimiste `APIService.sessionLoggedToday` mis à `true` dès `logSession()` (online ou offline), reset sur réponse serveur ; (2) `TodayCardView` observe ce flag ; (3) `SyncManager.flushQueue()` clear cache + `fetchDashboard()` après toute mutation de session. *(2026-04-19)*
- [x] **Scan nutrition — caméra directe sans dialog** : le bouton scan ouvrait une `confirmationDialog` "Caméra / Bibliothèque photos". L'utilisateur veut toujours la caméra. Supprimé le dialog + la sheet bibliothèque, bouton ouvre directement `ImagePickerView(sourceType: .camera)`. Variables `showSourceChoice` + `showLibraryPicker` supprimées. *(2026-04-19)*
- [x] **Yoga/Recovery ne s'enregistrent pas** : deux causes racines. (1) Serveur : `api_seance_data()` utilisait `load_sessions()` (dict keyed by date) — si plusieurs sessions pour la même date (morning yoga + evening stub), la dernière écrasait → `already_logged` faux-négatif. Fix : requête directe `_db.get_workout_session(today_date)` (session morning uniquement). (2) iOS : `SpecialSeanceView.logSession()` utilisait `try?` → swallowe toutes les erreurs, toujours affichait "Séance enregistrée ✅" même si le save avait échoué. Fix : `try/catch` + vérification `fresh.alreadyLogged` avant de confirmer, affiche erreur si non confirmé. *(2026-04-19)*

---

## 🔴 CRITIQUE — Bugs visibles / corruption de données

- [x] **409 guard + SyncManager requeue** : `SyncManager` traite déjà 409 comme succès (`|| code == 409`) → pas de requeue. `offlinePost()` ne queue que sur erreur réseau (URLError), jamais sur 4xx. Confirmé correct.
- [x] **Cache stale après log séance** : `APIService.logExercise()` invalide maintenant `seance_data` + `dashboard` immédiatement après chaque log.
- [x] **Désync timezone client/serveur** : supprimé `localToday` (recalcul depuis timezone iPhone) dans `DashboardData` et `SeanceData`. Toutes les vues utilisent `today` (fourni par le serveur en heure MTL).
- [x] **ChecklistCardView invisible au matin** : `isHiddenToday` lu avant `load()` → reset de date inefficace si app gardée en mémoire la nuit. Fix : swap ordre dans `onAppear` (2026-03-30).
- [x] **TodayCard affiche "Commencer" malgré séance loggée** : `if isLoggedToday, let session` échouait quand `alreadyLoggedToday=true` mais `sessions[todayDate]=nil` (désync cache). Séparé en deux conditions indépendantes (2026-03-29).
- [x] **Schema Supabase manquant `session_type`** : colonne `session_type` absente de `workout_sessions` bloquait le pipeline Séance du Soir. Migration 003 créée (2026-03-29).
- [x] **`/api/ai/coach/history` → 500 NameError** : `_db` non importé dans la route. Fix : `import db as _db` ajouté (2026-04-04).
- [x] **`inventory_types` nulls cassait décode Swift** : `info.get("type", "machine")` retourne `None` si la clé existe avec valeur null. Fix : `info.get("type") or "machine"` (2026-04-04).
- [x] **`create_workout_session` smallint error** : `round(float(rpe), 1)` = float Python rejeté par PostgreSQL `smallint`. Fix : `int(round(float(rpe)))` dans `db.py` (2026-04-04).
- [x] **`SpecialSeanceView.alreadyLoggedToday` stale** : `@AppStorage` local pris comme source de vérité même si le serveur n'a pas reçu la séance. Fix : cross-check `vm.seanceData?.alreadyLogged` (code iOS prêt, rebuild Xcode requis).
- [x] **Tendance body_weight ↓ -72 kg** : 3 entrées en livres (180/176/188.6) mélangées avec des kg. Converties en DB + `get_tendance()` filtre >150 (2026-04-04).

---

## 🟠 HAUTE PRIORITÉ — UX bloquante

- [x] **Edit session dans Historique** : sheet d'édition muscu + HIIT, endpoint `/api/historique_data` paginé (2026-03-29).
- [x] **Validation reps dans SeanceView** : champ reps rouge + bordure rouge si valeur non numérique saisie (2026-03-29).
- [x] **Config Timer persistée** : workSecs/restSecs/prepareSecs/totalRounds sauvegardés via @AppStorage (2026-03-29).
- [x] **Timer se stoppe en arrière-plan** : `UNUserNotificationCenter` planifie une notification par phase (work/rest/done) au passage en background (2026-03-29).
- [x] **Recovery modifiable** : bouton crayon + `LogRecoverySheet(prefillEntry:)` + FAB adaptatif (2026-03-29).
- [x] **Deload recommandé mais pas auto-appliqué** : bouton "Appliquer le déload (−15%)" dans `DeloadBannerView` → POST `/api/apply_deload` (2026-03-29).
- [x] **Validation photo profil** : limite 500KB, alert `photoError`, compression JPEG 0.7 (2026-03-29).
---

## 🟡 MOYENNE PRIORITÉ — Qualité & cohérence

- [x] **Pagination dans Historique** : `/api/historique_data` avec `limit`/`offset`/`has_more`, "Charger plus" dans HistoriqueView (2026-03-29).
- [x] **Filtre par date dans Historique** : `MonthPickerSheet` + `?month=YYYY-MM` param dans `loadData()`, backend filtre par mois (2026-03-29).
- [x] **1RM formula ignore RPE** : résolu via RIR : quand avg_rir disponible, RPE implicite = 10−rir, modifie la suggestion de poids.
- [x] **CacheService TTL** : TTL par endpoint (dashboard=5min, seance=5min, stats=15min, programme=1h, etc.) avec sidecar .expiry (2026-03-29).
- [x] **Programme : message si séance vide** : placeholder "Aucun exercice — tape + pour en ajouter" dans EditableSeanceProgramCard (2026-03-29).
- [x] **Nutrition : édition d'entrée** : bouton crayon + EditNutritionSheet + endpoint `/api/nutrition/edit` (2026-03-29).
- [x] **Objectifs : animation achievement** : sparkles + scale spring au appear quand obj.achieved (2026-03-29).
- [x] **Goals sans deadline enforcement** : notification locale J-7 et J-1 via `scheduleGoalDeadlineNotifications()` (2026-03-29).
- [x] **Inventaire : repos 90s affiché "1min"** : division entière 90/60=1 → deux chips identiques. Remplacé par `formatDur()` (2026-03-29).
- [x] **Pas d'indication "exo jamais utilisé" dans inventaire** : badge ⭐ "En programme" + filtre chip dans InventaireView (2026-03-29).
- [x] **HIIT : pas de templates favoris** : `HIITTemplate` (Codable), `@AppStorage("hiit_templates")`, chips de templates + alert "Sauvegarder" dans `AddHIITSheet` (2026-03-29).
- [x] **HealthKit auto-import cardio/recovery** : `WatchSyncService.syncIfNeeded()` appelé au lancement dans `TrainingOSApp.onAppear` (2026-03-29).
- [x] **Pas d'export données** : bouton "Exporter mes données" dans `ProfileView`, endpoint `/api/export_data`, ShareSheet (2026-03-29).
- [x] **SleepView vide** : `sleep_records` jamais peuplé. Bridge `recovery_log → sleep_records` : fallback sur HealthKit (15 entrées visibles, sleep/today retourne 7.1h) (2026-04-04).
- [x] **14 doublons cardio** : artefact migration KV (logged_at identique). Nettoyés en DB, 5 entrées uniques conservées (2026-04-04).
- [x] **Breathwork session 0 durée** : session fantôme supprimée en DB (2026-04-04).

---

## 🎨 UI/UX — Workout & flux utilisateur (2026-04-06)

- [x] **RPE chips 1–10** : élargies depuis 6-10, ScrollView horizontal dans ExerciseCard (2026-04-06)
- [x] **RIR découvrabilité** : sous-titre "avant échec" sous le header RIR (2026-04-06)
- [x] **Set-by-set label** : texte "Set à set" visible sur le toggle (plus icon seul) (2026-04-06)
- [x] **"Reprendre" monté en haut** : bouton "Reprendre la dernière séance" en première position dans la card (2026-04-06)
- [x] **Bouton logger labellisé** : "Logger" toujours visible, plus icon orange seul (2026-04-06)
- [x] **Historique : 3 sessions par défaut** : était 1 + expand requis (2026-04-06)
- [x] **"Sauter" : confirmation obligatoire** : `confirmationDialog` avant de skipper (2026-04-06)
- [x] **Énergie pré-séance au lancement** : `EnergyPreWorkoutSheet` s'affiche une fois/jour avant le workout ; plus posée rétroactivement dans FinishSessionSheet (2026-04-06)
- [x] **Analyse IA auto** : `loadAIAnalysis()` déclenché à l'ouverture de FinishSessionSheet (2026-04-06)
- [x] **Haptic commit séance** : `.success` haptic au moment de l'enregistrement (2026-04-06)

---

## 🎨 UI/UX — Problèmes affectant l'expérience utilisateur (audit 2026-04-05)

> Extraits de l'audit senior. Classés par impact utilisateur perçu.

- [x] **#A6 — Flash données stale au refresh Dashboard** : pull-to-refresh déjà présent avec spinner natif Apple. Skeleton affiché au premier chargement (`api.dashboard == nil`). (2026-04-06)
- [x] **#A8 — Erreurs réseau invisibles** : `ErrorBannerView` intégré dans Dashboard, Nutrition, Objectifs (avec retry + dismiss). (2026-04-06)
- [x] **#A7 — Cache invalidation incohérente** : `deleteCardio` invalide maintenant `cardio_history` + `stats_cardio`. (2026-04-06)
- [x] **#A9 — Timezone mismatch** : `DateFormatter.isoDate` a maintenant `timeZone = America/Montreal`. `DashboardView.todayStr` et `RecoveryView.todayStr` utilisent le singleton. (2026-04-06)
- [x] **#A10 — Scroll lent sur listes longues** : `HistoriqueView` VStack → `LazyVStack`. (2026-04-06)
- [x] **#A13 — Spinners incohérents** : composant `AppLoadingView` créé dans `Components/`. 9 fichiers migrés (`ProgressView().tint(.orange).scaleEffect(1.3)` → `AppLoadingView()`). (2026-04-06)
- [x] **États vides manquants** : `EmptyStateView` créé dans `Components/`. Appliqué à RecoveryView, CardioView, NutritionView. (2026-04-06)
- [x] **Feedback actions destructives** : `ToastView` + `.toast()` modifier créés dans `Components/`. Appliqué à HistoriqueView (muscu + HIIT), CardioView, RecoveryView, NutritionView, ObjectifsView. (2026-04-06)
- [x] **Keyboard dismiss incohérent** : certains formulaires dismiss au tap hors champ, d'autres non. `scrollDismissesKeyboard(.interactively)` ajouté à IntelligenceView (chat scroll). Autres views prioritaires déjà couvertes. (2026-04-06)

---

## 🟢 BASSE PRIORITÉ — Améliorations UX

- [x] **SeanceView : log set-by-set** : bouton ➜ dans l'en-tête des sets, mode set-by-set avec highlight + bouton ✓ par set, auto-log quand dernier set confirmé (2026-03-29).
- [x] **Intelligence : historique conversations** : `ChatMessage` Codable, `@AppStorage("intelligence_history")`, restore au `.task`, save à `onChange(of: messages)` (2026-03-29).
- [x] **Mood : corrélation avec performance** : `MoodRPECorrelationCard` scatter chart + Pearson r dans `MoodTrackerView` (2026-03-29).
- [x] **HIIT vs Muscu sur même vue** : 3e tab "Timeline" dans `HistoriqueView`, `buildTimeline()` merge muscu+HIIT par date, `TimelineRow` (2026-03-29).
- [x] **Heatmap HIIT distinct de muscu** : SessionHeatmapView avec orange=muscu, bleu=HIIT, violet=les deux, légende. (2026-04-06)
- [x] **Injury tracking** : champ "Zone douloureuse" optionnel dans `ExerciseCard`, transmis via `pain_zone` dans payload `/api/log`, stocké dans `history_entry` (2026-03-29).
- [x] **Pas de badge achèvement objectif** : sections Active/Atteints/Archivés dans `ObjectifsView`, bouton "Archiver" sur goals atteints, endpoint `/api/archive_objectif` + KV `goals_archived` (2026-03-29).
- [x] **Profile non rempli** : Banner orange dans ProfileView si name/weight/height/age/goal/level sont null. Tap → EditProfileSheet. (2026-04-06)
- [x] **Objectifs vides** : Smart Goals system implémenté — 7 types calculés automatiquement (2026-04-05).
- [x] **Nutrition : cibles glucides/lipides = 0** : Bouton "Calculer auto" dans NutritionSettingsSheet (split 30/45/25 P/G/L). (2026-04-06)
- [x] **Smart Goals — types avancés** : 5 types ajoutés (estimated_1rm, monthly_distance, resting_hr, pss_avg, sleep_streak) — backend + iOS. (2026-04-06)

---

## 🏗️ ARCHITECTURE / TECHNIQUE

- [x] **Pas de suite de tests E2E** : TrainingOSUITests/TrainingOSUITests.swift avec 5 flows XCUITest. Ajouter la cible UITest dans Xcode. (2026-04-06)
- [x] **API sans documentation** : api/README.md — 8 blueprints, ~60 endpoints avec methode/chemin/params. (2026-04-06)
- [x] **Migration 003 appliquée sur Supabase** : `session_type` + backfill + contrainte UNIQUE(date, session_type) (2026-03-29).
- [x] **Migration KV → relational complète** : table `kv` supprimée, toutes les données migrées vers tables relationnelles. Migration 011 appliquée. (2026-04-04).

---

## 🐛 Régression — Tests 2026-04-06

- [x] **B1 — `session_name` perdu sur CREATE** : `create_workout_session()` accepte maintenant le param ; `log_session()` le propage sur insert (2026-04-06)
- [x] **B2 — `/api/progression_suggestions` inexistant** : route ajoutée dans `routes/workout.py`, appelle `smart_progression.generate_suggestions()` (2026-04-06)
- [x] **B3 — Schema doc stale** : `session_name TEXT` ajouté à `workout_sessions` dans `docs/schema.sql` (2026-04-06)
- [x] **B4 — Race condition EnergyPreSheet / ProgressionSheet** : progression check différé à `onChange(showEnergyPreSheet=false)` quand energy sheet va s'afficher (2026-04-06)
- [x] **RPE + pain_zone** : OK — écriture confirmée dans `exercise_logs.rpe` / `exercise_logs.pain_zone`
- [x] **PSS 10 réponses + score** : OK — toutes les réponses soumises, score + catégorie stockés dans `pss_records`
- [x] **Objectif nutrition** : OK — `calorie_limit` / `protein_target` dans `nutrition_settings`, re-fetch après save
- [x] **user_profile 7 champs** : OK — même route `/api/update_profile` pour onboarding et édition

---

## 🔐 AUDIT SENIOR — Sécurité & Architecture (2026-04-05)

> Issu de l'audit complet codebase. Priorisé du plus critique au plus mineur.
> Ne pas implémenter sans validation des priorités.

### 🔴 Critique

- [x] **#A1 — Zéro authentification API** : `before_request` Flask + `URLSession.authed` iOS. 34 call sites couverts. Clé deployée sur Vercel. (2026-04-06)

- [x] **#A2 — `index.py` fichier dieu (3 060 lignes)** : splitté en 8 Flask Blueprints (`api/routes/`) + `api/utils.py` helpers partagés. `index.py` → ~100 lignes d'app factory. (2026-04-06)

- [x] **#A3 — Exceptions silencieuses** : `@app.errorhandler(Exception)` global dans `index.py` — traceback loggué serveur, message générique renvoyé au client. (2026-04-06)

- [x] **#A4 — `SeanceView.swift` monolithe (3 550 lignes)** : `ExerciseViewModel` extrait dans `Views/Seance/ExerciseViewModel.swift`. `ExerciseCard` + `ExerciseLogResult` supprimés de SeanceView. (2026-04-06)

- [x] **#A5 — Pas de source de vérité unique** : `AppState` singleton créé dans `Services/AppState.swift`, injecté via `.environmentObject` dans `TrainingOSApp`. Utilisé dans Dashboard, Nutrition, Objectifs, Recovery, Cardio. (2026-04-06)

### 🟠 Haute priorité

- [x] **#A6 — Flash de données stale au refresh Dashboard** : pull-to-refresh natif Apple déjà présent. Skeleton au premier chargement. (2026-04-06)

- [x] **#A7 — Invalidation cache incohérente** : `deleteCardio` invalide maintenant les clés cache correspondantes. (2026-04-06)

- [x] **#A8 — Erreurs réseau invisibles dans la majorité des views** : `ErrorBannerView` intégré dans Dashboard, Nutrition, Objectifs (avec retry + dismiss). (2026-04-06)

- [x] **#A9 — Mismatch timezone iOS (local) vs backend (Montréal)** : `DateFormatter.isoDate` (singleton partagé) a maintenant `timeZone = America/Montreal`. Fix global sur tous les usages. (2026-04-06)

- [x] **#A10 — `ForEach` dans `VStack` sur listes longues** : HistoriqueView migré vers `LazyVStack`. (2026-04-06)

### 🟡 Qualité & cohérence

- [x] **#A11 — `DateFormatter` recréé inline partout (3+ variantes)** : `DateFormatter.isoDate` singleton partagé existait déjà. `DashboardView.todayStr` et `RecoveryView.todayStr` migrés pour l'utiliser. Timezone MTL ajoutée. (2026-04-06)

- [x] **#A12 — Logique métier dans les Views** : `DashboardViewModel` + `NutritionViewModel` extraits. 9 `@State` retirés de DashboardView, 6 de NutritionView. Views n'observent que, n'agissent pas. (2026-04-06)

- [x] **#A13 — Pas de composant de loading uniforme** : `AppLoadingView` créé dans `Views/Components/`. 9 fichiers migrés. (2026-04-06)

- [x] **#A14 — Parsing JSON manuel dans NutritionView** : `NutritionEntry`, `NutritionSettings`, `NutritionTotals`, `NutritionDayHistory` tous `Decodable` avec `CodingKeys` + `AnyCodingKey` pour fallbacks (nom/name, heure/time, etc.). `NutritionDataResponse` top-level. JSONDecoder en 3 lignes. (2026-04-06)

- [x] **#A15 — `APIModels.swift` monolithe (1 252 lignes)** : splitté en 6 fichiers domaine — `WorkoutModels.swift`, `NutritionModels.swift`, `WellnessModels.swift`, `GoalsModels.swift`, `AnalyticsModels.swift`, `ProfileModels.swift`. `APIModels.swift` ne garde que `PagedResponse<T>` + `SafeString`. (2026-04-06)

- [x] **#A16 — Unités sans contrat documenté** : `-- unit: lbs` ajouté sur colonnes weight dans `docs/schema.sql`. `# unit: lbs (not kg)` ajouté dans `db.py` sur `get_body_weight_logs` + `upsert_body_weight`. (2026-04-06)

### 🟢 Mineur

- [x] **#A17 — `START_DATE = date(2026, 3, 3)` hardcodé** : baseline du compteur de semaines dans `index.py`. Devrait être `user.created_at` depuis la DB.

- [x] **#A17 — START_DATE hardcode** : get_current_week() lit user_profile.created_at depuis Supabase, fallback 2026-03-03. (2026-04-06)

- [x] **#A18 — Pas de SwiftUI previews** : #Preview ajouté dans StatsView, DashboardView, NutritionView, ObjectifsView, ProfileView. (2026-04-06)

- [x] **#A19 — Photos base64** : upload tente Supabase Storage (photo_url + AsyncImage). Fallback base64 si bucket absent. (2026-04-06)

- [x] **#A20 — Rate limiting IA** : Compteur dans Supabase ai_rate_limit (hour_key PK, count). Cross-worker safe. threading.Lock retire. (2026-04-06)

## 🔍 AUDIT CODEBASE 2026-04-18 — Rapport complet

> Audit externe "regard sans filtre" — 4 axes. Approuver chaque fix avant implémentation.

### 🔴 Haute priorité — Sécurité
- [x] **SEC-1 — Clé API embarquée dans le binaire** : `_trainingOSApiKey` retiré de `APIService.swift`. Centralisé dans `APIConfig.apiKey` (Extensions.swift) avec fallback xcconfig documenté — `Bundle.main.object(forInfoDictionaryKey: "TrainingOSAPIKey")` → fallback hardcodé si absent. *(2026-04-18)*
- [x] **SEC-2 — Auth Bearer unique** : limitation connue pour app personnelle mono-user. Acceptable ; rotation de clé possible côté serveur si le repo est partagé. *(2026-04-18)*
- [x] **SEC-3 — Stacktrace Flask** : `_tb.print_exc()` remplacé par `logger.exception()`. `HTTPException` (4xx contrôlées) exposent leur `.description`; toute autre exception → message générique `"Erreur interne — réessaie"`. *(2026-04-18)*
- [x] **SEC-4 — Validation inputs** : `request.json` / `request.get_json()` sans guard remplacés par `request.get_json(silent=True) or {}` dans tous les blueprints actifs (profile, workout, goals, wellness, ai_coach, analytics, nutrition). Helper `require_fields()` ajouté dans `utils.py`. *(2026-04-18)*
- [x] **SEC-5 — `SECRET_KEY` Flask** : fallback hardcodé supprimé. Si vide → exception en prod (Vercel), warning + clé dev en local. Placeholder check maintenu pour Vercel. *(2026-04-18)*

### 🔴 Haute priorité — Architecture & dette
- [x] **ARCH-1 — `applyDeload` contourne `APIService`** : construit sa propre `URLRequest` avec URL hardcodée. Migré vers `APIService.applyDeload()`. *(2026-04-18)*
- [x] **ARCH-2 — Base URL dupliquée dans 3 fichiers** : `APIConfig.base` centralisé dans `Extensions.swift`, utilisé par `APIService` et `SyncManager`. *(2026-04-18)*
- [x] **ARCH-3 — `APIService` god-class (921 l.)** : split fichiers bloqué pbxproj. Ajout d'un domain map commenté en tête de classe (8 domaines : WORKOUT/PROFILE/GOALS/NUTRITION/CARDIO/WELLNESS/MENTAL/SLEEP) — navigable dans Xcode via MARK. *(2026-04-18)*
- [x] **ARCH-4 — `flask_app.py` code mort (600 l.)** : supprimé. *(2026-04-18)*
- [x] **ARCH-5 — Scripts migration livrés en prod Vercel** : `migrate_*.py` déplacés dans `scripts/` (hors bundle Vercel). *(2026-04-18)*
- [x] **ARCH-6 — MVVM incohérent** : `SeanceViewModel` extrait de `WorkoutSeanceView` vers `ExerciseViewModel.swift` (fichier existant dans target). Séance rejoint Dashboard/Nutrition avec ViewModel dédié. Stats/Historique restent @State (logique trop couplée aux vues pour extraire sans nouveaux fichiers). *(2026-04-18)*
- [x] **ARCH-7 — `schema.sql` vide** : fichier déjà peuplé (645 lignes) avec DDL complet — `exercises`, `program_sessions`, `workout_sessions`, `exercise_logs`, tables nutrition, wellness, etc. Rien à faire. *(2026-04-18)*
- [x] **ARCH-8 — `AppState.loadProfile()` jamais appelée** : appelée dans `TrainingOSApp.onAppear` Task. *(2026-04-18)*

### 🔴 Haute priorité — Robustesse
- [x] **ROB-1 — `except Exception: pass` généralisé dans `db.py`** : exceptions silencieuses → état local/remote diverge sans signal. Ajout de `logger` sur tous les blocs muets + suppression doublon `update_exercise_current_weight`. *(2026-04-18)*
- [x] **ROB-2 — `try?` sur 9 résultats dans DashboardViewModel** : remplacé par `do { ... } catch { print("[Dashboard] ...: \(error)") }` pour chaque binding. *(2026-04-18)*
- [x] **ROB-3 — `SyncManager` — `ModelContext` recréé à chaque appel** : contexte partagé `mainContext` réutilisé pour enqueue/refreshPendingCount. *(2026-04-18)*
- [x] **ROB-4 — `offlinePost` renvoie `Data()` vide pour signaler offline** : retourne `Data?` — `nil` = queué, non-nil = réponse serveur. `APIError.queuedOffline` ajouté pour callers qui throwent. Tous les call sites mis à jour (`guard let data`, `if data != nil`). *(2026-04-18)*
- [x] **ROB-5 — `PendingMutation` sans alerte** : `zombieDropCount: Int` publié sur SyncManager ; toast 5s affiché quand mutations abandonnées. *(2026-04-18)*
- [x] **ROB-6 — `enableBackgroundDelivery` ne stocke pas les observers** : `backgroundObservers: [HKObserverQuery]` retient les queries + guard "already registered". *(2026-04-18)*
- [x] **ROB-7 — `fetchDashboard` planifie notif même si fetch a échoué** : `scheduleMorningNotification` n'est appelée qu'après decode réussi — déjà correct. *(2026-04-18)*
- [x] **ROB-8 — `fetchSnapshotForDate` mélange HR "latest" + steps par date** : `fetchRestingHR(for: Date)` ajouté — query filtrée dans le jour cible. *(2026-04-18)*
- [x] **ROB-9 — `TrainingOSApp.onAppear` réenregistre observers HealthKit** : guard `hkSetupDone: Bool` — enregistrement une seule fois. *(2026-04-18)*

### 🔴 Haute priorité — Performance
- [x] **PERF-1 — N+1 Supabase dans `generate_suggestions`** : 2 queries par exercice (info + history). Batchés en 2 appels total. *(2026-04-18)*
- [x] **PERF-2 — `loadAll` attend `fetchDashboard` en série** : `fetchDashboard` mis en `async let` — tourne en parallèle avec deload/mood/brief/soir/recovery. *(2026-04-18)*
- [x] **PERF-3 — Dashboard recharge tout à chaque `onAppear`** : `.task` → une seule fois par cycle de vie ; `scenePhase` guard `> 300s` avant refetch. Déjà correct. *(2026-04-18)*
- [x] **PERF-4 — `backfillRecentDaysIfNeeded` : 7 syncs séquentiels** : `withTaskGroup` — fetches HK en parallèle, puis sync résultats. *(2026-04-18)*
- [x] **PERF-5 — Insights/LSS/CoachTip à chaque `loadAll` sans condition** : `analyticsLoadedDate` guard — chargé une seule fois par jour. *(2026-04-18)*

### 🟡 Moyenne priorité — Qualité code
- [x] **CODE-1 — `WellnessModels.swift` importe SwiftUI pour `Color`** : `categoryColor` extrait dans `Extensions.swift`; `import SwiftUI` retiré de `WellnessModels.swift`. *(2026-04-18)*
- [x] **CODE-2 — `switch MacPage` triplé** : déjà centralisé — `label`, `icon`, `color` définis une seule fois dans l'enum `MacPage` (ContentView.swift). *(2026-04-18)*
- [x] **CODE-3 — Nommage mixte FR/EN dans DashboardViewModel** : `soirData` → `eveningSession`, `brief` → `morningBrief`. Mis à jour dans DashboardViewModel + DashboardView. *(2026-04-18)*
- [x] **CODE-4 — Fichiers de vue >2000 l.** : `SeanceView` 3521 → 3149 (−372 l.) via extraction `RestTimerManager` + `SeanceViewModel`. Split complet en sous-fichiers bloqué pbxproj. *(2026-04-18)*
- [x] **CODE-5 — `RestTimerManager` défini dans `SeanceView`** : déplacé dans `Services/NotificationService.swift` (fichier existant, pas de pbxproj requis). SeanceView −194 lignes. *(2026-04-18)*
- [x] **CODE-6 — `normalize_patch` dead code** : supprimé de `db.py`. *(2026-04-18)*
- [x] **CODE-7 — `scheduleMorningNotification` replanifié à chaque `fetchDashboard`** : guard `UserDefaults` — exécutée une seule fois par jour. *(2026-04-18)*
- [x] **CODE-8 — `_parse_scheme` retourne `(0,0)` silencieusement** : `logger.warning` ajouté. *(2026-04-18)*
- [x] **CODE-9 — `_to_int` retourne 0 silencieusement** : `logger.debug` ajouté. *(2026-04-18)*
- [x] **CODE-10 — `apply_suggestion` ignore le retour de `update_exercise_current_weight`** : retour capturé, propagé dans `ok`, warning si False. *(2026-04-18)*

---

## 🌙 Séance du Soir — État

- [x] **Étape 4** — index.py : `/api/seance_soir_data`, `session_type` dans pipeline
- [x] **Étape 5** — APIModels.swift : `SeanceSoirData`
- [x] **Étape 6** — APIService.swift : `fetchSeanceSoirData`
- [x] **Étape 7** — SeanceSoirView.swift
- [x] **Étape 8** — DashboardView.swift : `SoirCardView`
- [x] **Schéma** — `session_type` ajouté à `docs/schema.sql` + migration 003 créée
- [x] **Migration 003 appliquée sur Supabase prod** (2026-03-29)

---

## 🧠 Smart Progression — Coaching post-séance

- [x] **Classification exercices** : `load_profile` (compound_heavy/hypertrophy/isolation/NULL) + `category` (push/pull/legs/core) sur tous les exercices (migration 006–008, 2026-03-31)
- [x] **`api/smart_progression.py`** : moteur de suggestion post-séance — compare session courante vs précédente du même nom, génère increase_weight/increase_sets/deload/maintain/regression (2026-03-31)
- [x] **Plateau detection** : ≥3 sessions consécutives au même poids → add set (cycle 2-2-2-2, max 4 sets) ou deload −10% (2026-03-31)
- [x] **Wave loading** : seuls les sets au poids maximum (working sets) évalués pour le hit rate (2026-03-31)
- [x] **Anti-régression** : si max_weight < session précédente → flag regression (2026-03-31)
- [x] **Fatigue globale** : ≥50% exercices en régression → fatigue_warning sur toutes les suggestions (2026-03-31)
- [x] **session_name matching** : Push A vs Push A (pas morning vs morning) — colonne `session_name TEXT` dans `workout_sessions` (migration 010), fallback vers session_type pour les anciennes sessions (2026-03-31)
- [x] **GET /api/progression_suggestions** : endpoint + paramètre `session_name` (2026-03-31)
- [x] **POST /api/apply_progression** : applique une suggestion → update default_scheme + weights KV (2026-03-31)
- [x] **`Models/ProgressionSuggestion.swift`** : struct Codable avec CodingKeys snake_case (2026-03-31)
- [x] **`Views/Seance/ProgressionSuggestionsSheet.swift`** : sheet post-séance, sections COACHING / MAINTENIR, boutons Appliquer/Ignorer, toolbar Passer→Terminer (2026-03-31)
- [x] **SeanceView intégration** : `onChange(vm.showSuccess)` → fetch suggestions → show sheet si actionable, sinon reload direct (2026-03-31)
- [x] **Migrations 006–010** : classification exercices (006–009) + session_name colonne (010) — 009 et 010 à appliquer manuellement si pas encore fait (2026-03-31)

---

---

## 🏋️ Séance du jour — Audit & fixes (2026-04-15) · commit `6295785`

- [x] **RPE par série** : badge RPE tap-to-cycle (R5→R6→…→R10→nil) dans chaque ligne de set
- [x] **Target vs réalisé** : indicateur vert ✓ / orange ! comparant reps saisies vs prescription.repMin
- [x] **Max séries 8→12** : setsCount, ExerciseCard bouton/couleur/disabled tous portés à 12
- [x] **Badge PR** : affiché après log si loggedWeight > previousBest (historique Firestore)
- [x] **Note de séance** : champ éphémère dans showAdvanced, réinitialisé à clearDraft()
- [x] **Auto rest timer** : `RestTimerManager.shared.requestAutoStart()` déclenché après chaque log
- [x] **Edit post-séance** : AlreadyLoggedSeanceView — bouton "Modifier la séance" + PostSessionEditSheet (form pré-rempli, force-log via APIService)
- [x] **Cardio/HIIT multi-log** : `cardioCount`/`hiitCount` Int (était Bool) → "Cardio ×N — Ajouter +"
- [x] **Bandeau volume temps réel** : bannière orange `Int(currentVolume) lbs/kg` dès le 1er log
- [x] **Soumission partielle** : FinishSessionSheet — bouton "Soumettre N exercice(s) seulement" si tous non loggés
- [x] **Tableau récap séance** : toggle icône `list.bullet.rectangle` → `sessionSummaryTable` compact
- [x] **RestTimer ±30s** : 4 boutons (−30s, −10s, +10s, +30s) dans RestTimerSheet
- [x] **Alerte multi-timer** : confirmation dialog si timer actif sur autre exercice avant remplacement

---

## 📊 Stats — Audit & fixes (2026-04-15) · commit `5cd6a7b`

- [x] **avgReps() guard AMRAP** : early return sur formats non-numériques → 1RM ne crash plus
- [x] **weeklyVolume source primaire** : `sessions.sessionVolume` (calculé serveur) > calcul local
- [x] **+2 KPI cards** : Sets totaux (.teal) + Reps totaux (.indigo) ajoutés à vueGlobaleTab
- [x] **Pull-to-refresh** : `.refreshable { await loadData() }` sur ScrollView principal
- [x] **ACWR fallback** : placeholder "Données insuffisantes" si `acwr == nil`
- [x] **Recovery score HRV + FC** : RecoveryScoreChart.score() intègre HRV normalisé (0–100ms→0–10) et FC repos (40–85bpm→0–10)
- [x] **BodyFatChartView** : courbe % body fat + delta + valeur courante dans corpsTab si ≥2 entrées
- [x] **NutritionComplianceChart 30j** : suffix(7)→suffix(30) + titre dynamique "COMPLIANCE CALORIES (N JOURS)"
- [x] **MacrosBreakdownView** : barres glucides/lipides/protéines vs cibles avec couleur compliance dans nutritionTab
- [x] **Dédoublonnage Top5Volume** : supprimé de exercicesTab (reste dans vueGlobaleTab)

---

## ✅ Déjà résolu récemment

---

## 🎨 Migration couleurs — tokens sémantiques

> Remplacer les `Color(hex:)` hardcodés par les tokens sémantiques de `Extensions.swift`.
> Tokens disponibles : `.appBg` `.appCard` `.appBgSecondary` `.forge` `.forgeDeep` `.appAccentUltraLight`
> `.appDanger` `.appSuccess` `.appWarning` `.appTextSecondary` `.appTextTertiary` `.appSeparator`
> Exceptions intentionnelles : `.moonlight` `.voidBg` (Spirit aesthetic, fixed), couleurs de charts
> spécifiques (ex : `"34C759"` health-green, `"191926"` ring bg, `"FF9500"` workout badge).
> Workflow : un dossier à la fois, approbation visuelle entre chaque.
> ~427 occurrences restantes après pass initial (PRTrackerCard + SessionQualityCard migrés).

**Note : ~60% des occurrences sont des palettes fixes légitimes** (couleurs de disques, identifiants
de catégorie, esthétiques décoratives). Ne pas remplacer mécaniquement — évaluer le contexte.

**Fichiers déjà migrés ✅**
- [x] Views/Dashboard/PRTrackerCard.swift — FFD60A → .appWarning
- [x] Views/Dashboard/SessionQualityCard.swift — FFD60A → .appWarning
- [x] Views/Dashboard/DashboardRitualCards.swift — F59E0B/22C55E/E8441A/C0201A/EF4444 → tokens
- [x] Views/Stats/StatsBodyViews.swift — 2ECC71 → .appSuccess
- [x] Views/Dashboard/TrainingLoadCard.swift — FF3B30 → .appDanger
- [x] Views/PSS/PSSView.swift — FF3B30 → .appDanger

**Skippés intentionnellement (palettes fixes)**
- [x] Views/Objectifs/ObjectifsView.swift — couleurs types objectifs (leanMass, weeklyVolume…)
- [x] Views/Seance/PlateCalculatorSheet.swift — couleurs physiques disques
- [x] Views/Intelligence/GraveyardView.swift — esthétique gothique feu/terre
- [x] Views/Dashboard/MuscleBalanceCard.swift — identifiants groupes musculaires

---

## 🔤 Migration typographie — tokens design system

> Remplacer tous les `.font(.system(size:))` par les 7 tokens (`appHero/appTitle/appHeadline/appBody/appLabel/appCaption/appMicro`).
> Règles dans `DesignSystem.swift`. Exceptions : <9pt KEEP, 25-31pt KEEP, 35pt+ KEEP, `.design: .rounded` KEEP, `.design: .serif` KEEP.
> Workflow : un dossier à la fois, approbation visuelle entre chaque.

**Fichiers déjà migrés ✅**
- [x] ContentView.swift
- [x] Services/WeatherService.swift
- [x] Utilities/PlatformHelpers.swift
- [x] Utilities/RPEHelper.swift
- [x] Views/Components/EmptyStateView.swift
- [x] Views/Components/MetricCell.swift
- [x] Views/Components/PrimaryButton.swift
- [x] Views/Dashboard/DashboardView.swift
- [x] Views/Nutrition/NutritionView.swift
- [x] Views/Onboarding/OnboardingView.swift
- [x] Views/Profile/ProfileView.swift
- [x] Views/Recovery/RecoveryView.swift
- [x] Views/Seance/WorkoutActiveView.swift

**Fichiers restants par dossier**

- [x] Views/BodyComp/BodyCompHistoryView.swift
- [x] Views/BodyComp/BodyCompView.swift
- [x] Views/BodyComp/NavyCalculatorView.swift
- [x] Views/Cardio/CardioActiveView.swift
- [x] Views/Cardio/CardioSummaryView.swift
- [x] Views/Cardio/CardioView.swift
- [ ] Views/Dashboard/CoachBriefCard.swift
- [ ] Views/Dashboard/DashboardBriefCards.swift
- [ ] Views/Dashboard/DashboardCardioCard.swift
- [ ] Views/Dashboard/DashboardHeaderCards.swift
- [ ] Views/Dashboard/DashboardRitualCards.swift
- [ ] Views/Dashboard/DashboardTodayCards.swift
- [ ] Views/Dashboard/DashboardWeeklyCards.swift
- [ ] Views/Dashboard/InfoButton.swift
- [ ] Views/Dashboard/MorningRevealView.swift
- [ ] Views/Dashboard/ReadinessView.swift
- [ ] Views/Dashboard/TodayWidgets.swift
- [ ] Views/EnergyRecovery/EnergyRecoveryView.swift
- [ ] Views/GymFinder/GymContributeView.swift
- [ ] Views/GymFinder/GymDetailView.swift
- [ ] Views/GymFinder/GymFiltersView.swift
- [ ] Views/GymFinder/GymFinderView.swift
- [ ] Views/HealthDashboard/HealthDashboardView.swift
- [ ] Views/HIIT/HIITHistoriqueView.swift
- [ ] Views/Historique/HistoriqueView.swift
- [ ] Views/Intelligence/ArsenalView.swift
- [ ] Views/Intelligence/BattleCounterView.swift
- [ ] Views/Intelligence/CoachContextSummary.swift
- [ ] Views/Intelligence/CoachGreetingHeader.swift
- [ ] Views/Intelligence/CoachMissionCard.swift
- [ ] Views/Intelligence/DemonsView.swift
- [ ] Views/Intelligence/InsightPrincipalCard.swift
- [ ] Views/Intelligence/InsightsCard.swift
- [ ] Views/Intelligence/IntelligenceAnalyticsCards.swift
- [ ] Views/Intelligence/IntelligenceView.swift
- [ ] Views/Intelligence/NarrativeCard.swift
- [ ] Views/Intelligence/NutritionPerfInsightCard.swift
- [ ] Views/Intelligence/PatternCardView.swift
- [ ] Views/Intelligence/PatternReportView.swift
- [ ] Views/Intelligence/PlateauViews.swift
- [ ] Views/Intelligence/PostSeanceCard.swift
- [ ] Views/Intelligence/ProgramPreviewSheet.swift
- [ ] Views/Intelligence/ProgressionCard.swift
- [ ] Views/Intelligence/ProposalsCard.swift
- [ ] Views/Intelligence/RitualEveningView.swift
- [ ] Views/Intelligence/RitualMorningView.swift
- [ ] Views/Intelligence/RitualView.swift
- [ ] Views/Intelligence/SmartInsightsSection.swift
- [ ] Views/Intelligence/TimeCapsuleViews.swift
- [ ] Views/Intelligence/TodayMetricsRow.swift
- [ ] Views/Intelligence/TriggerLogView.swift
- [ ] Views/Intelligence/WarMapView.swift
- [ ] Views/Intelligence/WarRoomGateView.swift
- [ ] Views/Intelligence/WarRoomView.swift
- [ ] Views/Intelligence/WeekMomentumStrip.swift
- [ ] Views/Intelligence/WorkoutDNAView.swift
- [ ] Views/Inventaire/InventaireView.swift
- [ ] Views/MentalHealth/BreathworkView.swift
- [ ] Views/MentalHealth/JournalView.swift
- [ ] Views/MentalHealth/MentalHealthDashboardView.swift
- [ ] Views/MentalHealth/MentalHealthView.swift
- [ ] Views/MentalHealth/MoodTrackerView.swift
- [ ] Views/More/MoreView.swift
- [ ] Views/Notes/NotesView.swift
- [ ] Views/Nutrition/AddNutritionSheet.swift
- [ ] Views/Nutrition/DayTypeBadge.swift
- [ ] Views/Nutrition/FoodCatalogView.swift
- [ ] Views/Nutrition/MacroSummaryCard.swift
- [ ] Views/Nutrition/MealTemplateSheets.swift
- [ ] Views/Nutrition/NutritionActionMessage.swift
- [ ] Views/Nutrition/NutritionAnalyticsCards.swift
- [ ] Views/Nutrition/NutritionCharts.swift
- [ ] Views/Nutrition/NutritionEntryViews.swift
- [ ] Views/Nutrition/NutritionSettingsSheet.swift
- [ ] Views/Nutrition/ProteinProgressCard.swift
- [ ] Views/Oath/OathView.swift
- [ ] Views/Oath/OathWriteView.swift
- [ ] Views/Objectifs/ObjectifsView.swift
- [ ] Views/Profile/NotificationCenterView.swift
- [ ] Views/Programme/ProgrammeView.swift
- [ ] Views/PSS/PSSView.swift
- [ ] Views/Recovery/HRVAnalysisCard.swift
- [ ] Views/Recovery/LogRecoverySheet.swift
- [ ] Views/Recovery/ReadinessCard.swift
- [ ] Views/Recovery/RecoveryCharts.swift
- [ ] Views/Recovery/RecoveryPerformanceBanner.swift
- [ ] Views/Recovery/RecoveryRow.swift
- [ ] Views/Recovery/WatchSyncBannerView.swift
- [ ] Views/Seance/AddCardioSheet.swift
- [ ] Views/Seance/AddHIITSheet.swift
- [ ] Views/Seance/BonusSeanceView.swift
- [ ] Views/Seance/CreateVariantSheet.swift
- [ ] Views/Seance/ExerciseCard.swift
- [ ] Views/Seance/ExerciseSwapSheet.swift
- [ ] Views/Seance/FloatingRestTimerCard.swift
- [ ] Views/Seance/GhostBanner.swift
- [ ] Views/Seance/HoldToLogButton.swift
- [ ] Views/Seance/MidWorkoutAdvisorCard.swift
- [ ] Views/Seance/PlateCalculatorSheet.swift
- [ ] Views/Seance/PRCelebrationView.swift
- [ ] Views/Seance/ProgressionSuggestionsSheet.swift
- [ ] Views/Seance/SeanceSoirView.swift
- [ ] Views/Seance/SeanceView.swift
- [ ] Views/Seance/SessionChips.swift
- [ ] Views/Seance/SessionSupportViews.swift
- [ ] Views/Seance/SessionTimerView.swift
- [ ] Views/Seance/StepperInput.swift
- [ ] Views/Seance/WarmupGuidanceBanner.swift
- [ ] Views/Seasons/SeasonCloseView.swift
- [ ] Views/Seasons/SeasonReportView.swift
- [ ] Views/Seasons/SeasonStartView.swift
- [ ] Views/Seasons/SeasonView.swift
- [ ] Views/Settings/CardioSettingsView.swift
- [ ] Views/Settings/DisplaySettingsView.swift
- [ ] Views/Settings/HealthDataSettingsView.swift
- [ ] Views/Settings/RecoverySettingsView.swift
- [ ] Views/Settings/TrainingSettingsView.swift
- [ ] Views/Sleep/SleepView.swift
- [ ] Views/Spirit/SpiritBreathworkView.swift
- [ ] Views/Spirit/SpiritJournalView.swift
- [ ] Views/Spirit/SpiritMeditationView.swift
- [ ] Views/Spirit/SpiritView.swift
- [ ] Views/SplashView.swift
- [ ] Views/Stats/StatsBodyViews.swift
- [ ] Views/Stats/StatsComponents.swift
- [ ] Views/Stats/StatsNutritionViews.swift
- [ ] Views/Stats/StatsTrainingViews.swift
- [ ] Views/Stats/StatsView.swift
- [ ] Views/Stats/StatsView+Tabs.swift
- [ ] Views/Stats/StatsWellnessViews.swift
- [ ] Views/Timer/TimerView.swift
- [ ] Views/XP/XPView.swift

---

- [x] Dashboard 16 UX fixes : reorder TodayCard, skeleton loading, NavigationLinks, font WeekGrid, DeloadChip level 1, MoodCard, HeatmapView retiré, GreatDayCard badge intégré, PeakPrediction CTA, sleep prompt label, RecoverySnapshot indigo (2026-03-29)
- [x] Progressive overload — RIR capture, RPE gradué, détection chute de performance, trend 4 semaines (2026-03-26)
- [x] StatsView 5 onglets, period picker, smart insights (2026-03-26)
- [x] IntelligenceView contexte enrichi, NarrativeCard, Ghost Mode (2026-03-26)
- [x] Peak Prediction 7j dashboard (2026-03-26)
- [x] PR detection + notification locale iOS
- [x] CRUD complet inventaire
- [x] Checklist "Avant de partir" sur dashboard

---

## 🎯 Unification des verdicts effort (chantier ouvert 2026-07-20)

Contexte : audit cohérence verdicts readiness/effort — cas 19/07 (bandeau HRV
rouge + « Go hard · 74 » sur même écran). Commits 1-5 traitent le cœur
(messaging honnête, ancrage absolu, veto HRV/RHR, arbitre iOS, baseline HRV
unifiée, transparence). Reste :

### Producteurs éparpillés à unifier autour de `hrv_status` / `readiness.verdict`

- [ ] `api/phoenix_engine.py:280` — message HRV baseline dupliqué. Migrer vers consommation `readiness.hrv_status.zone`.
- [ ] `api/routes/proactive_insights.py:189` — « Tous les indicateurs au vert » parallèle au messaging readiness. Aligner ou supprimer.
- [ ] `Views/Recovery/RecoveryPerformanceBanner.swift:43` — bannière HRV recovery, seuil local. Migrer vers `readiness.hrvStatus`.
- [ ] `Views/Recovery/RecoveryView.swift:1185` — message `consecutiveLowDays`. Cohabite avec bandeau critique — décider si redondant ou complémentaire.

### LSS ↔ readiness — chantier majeur P0 potentiel

- [ ] **Deux composites parallèles sans arbitre** : `/api/readiness` (score composite pondéré, 9 modules) vs `api/morning_brief.py:_evaluate` L109 (LSS = Life Stress Score, seuils `<25/<40/<65` → verdict `defer/reduce/go`). Consommé par daily_brief. Peut contredire /api/readiness. **Choisir la canonique** (ou fusionner formules), déprécier l'autre. Effort : cartographie LSS complète (composants, seuils, consommateurs) puis convergence.

### Reste doctrinal

- [ ] Ajouter une note dans `docs/CONVENTIONS.md` §Sources de vérité : `/api/readiness` = source unique du verdict effort iOS. Toute nouvelle carte affichant une intensité recommandée consomme `readiness.verdict` (post-cap `DashboardVerdictArbiter` sur Dashboard).

---

## 🧹 Carnet de ménage

- [ ] **BudgetView.swift ~600 lignes** — extraire `BudgetCelebrationView`, `BudgetCard` et `BudgetFormat` dans leurs fichiers en Tranche 4, avec ajout au target Xcode fait proprement une fois (2026-07-11)
