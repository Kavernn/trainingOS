# TrainingOS — TODO & Améliorations

> Tour de l'app réalisé le 2026-03-15. Mis à jour le 2026-04-15 (séance + stats audit & fixes).
> Audit senior dev/UX ajouté le 2026-04-05 — 20 items priorisés.

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
- [ ] **ARCH-3 — `APIService` god-class (921 l.)** : 80+ endpoints + offline queue + cache + auth + notifs dans un seul fichier. Splitter par domaine (WorkoutAPI, NutritionAPI, WellnessAPI, etc.).
- [x] **ARCH-4 — `flask_app.py` code mort (600 l.)** : supprimé. *(2026-04-18)*
- [x] **ARCH-5 — Scripts migration livrés en prod Vercel** : `migrate_*.py` déplacés dans `scripts/` (hors bundle Vercel). *(2026-04-18)*
- [ ] **ARCH-6 — MVVM incohérent** : Dashboard/Nutrition ont un ViewModel, Séance/Stats/Historique ont la logique en `@State` dans la vue.
- [ ] **ARCH-7 — `schema.sql` vide** : schéma Supabase non versionné. Regénérer depuis prod via `supabase db dump` ou Supabase Studio → Export.
- [x] **ARCH-8 — `AppState.loadProfile()` jamais appelée** : appelée dans `TrainingOSApp.onAppear` Task. *(2026-04-18)*

### 🔴 Haute priorité — Robustesse
- [x] **ROB-1 — `except Exception: pass` généralisé dans `db.py`** : exceptions silencieuses → état local/remote diverge sans signal. Ajout de `logger` sur tous les blocs muets + suppression doublon `update_exercise_current_weight`. *(2026-04-18)*
- [ ] **ROB-2 — `try?` sur 9 résultats dans DashboardViewModel** : dashboard vide sans feedback ni log. Remplacer par gestion explicite.
- [x] **ROB-3 — `SyncManager` — `ModelContext` recréé à chaque appel** : contexte partagé `mainContext` réutilisé pour enqueue/refreshPendingCount. *(2026-04-18)*
- [ ] **ROB-4 — `offlinePost` renvoie `Data()` vide pour signaler offline** : ambigu avec réponse serveur vide légitime. Utiliser un type dédié (`OfflineResult`).
- [ ] **ROB-5 — `PendingMutation` sans TTL** : mutation qui échoue systématiquement retryée 5× et abandonnée sans alerte user.
- [ ] **ROB-6 — `HealthKitService.enableBackgroundDelivery` ne stocke pas les observers** : fuite mémoire, callbacks perdus si rappelée.
- [x] **ROB-7 — `fetchDashboard` planifie notif même si fetch a échoué** : `scheduleMorningNotification` n'est appelée qu'après decode réussi — déjà correct. *(2026-04-18)*
- [ ] **ROB-8 — `HealthKitService.fetchSnapshotForDate` mélange HR "latest" + steps par date** : snapshot incohérent.
- [x] **ROB-9 — `TrainingOSApp.onAppear` réenregistre observers HealthKit** : guard `hkSetupDone: Bool` — enregistrement une seule fois. *(2026-04-18)*

### 🔴 Haute priorité — Performance
- [x] **PERF-1 — N+1 Supabase dans `generate_suggestions`** : 2 queries par exercice (info + history). Batchés en 2 appels total. *(2026-04-18)*
- [x] **PERF-2 — `loadAll` attend `fetchDashboard` en série** : `fetchDashboard` mis en `async let` — tourne en parallèle avec deload/mood/brief/soir/recovery. *(2026-04-18)*
- [ ] **PERF-3 — Dashboard recharge tout à chaque `onAppear`** : vérifier TTL avant de refetch. CacheService a déjà des TTL — refetch actif seulement sur `.task` (une fois par cycle de vie vue).
- [x] **PERF-4 — `backfillRecentDaysIfNeeded` : 7 syncs séquentiels** : `withTaskGroup` — fetches HK en parallèle, puis sync résultats. *(2026-04-18)*
- [x] **PERF-5 — Insights/LSS/CoachTip à chaque `loadAll` sans condition** : `analyticsLoadedDate` guard — chargé une seule fois par jour. *(2026-04-18)*

### 🟡 Moyenne priorité — Qualité code
- [x] **CODE-1 — `WellnessModels.swift` importe SwiftUI pour `Color`** : `categoryColor` extrait dans `Extensions.swift`; `import SwiftUI` retiré de `WellnessModels.swift`. *(2026-04-18)*
- [ ] **CODE-2 — `switch MacPage` triplé** : couleur/icône par page définis dans 3 vues. Centraliser dans `MacPage` enum.
- [ ] **CODE-3 — Nommage mixte FR/EN dans DashboardViewModel** : `soirData` vs `brief`, `insights`. Uniformiser en anglais.
- [ ] **CODE-4 — Fichiers de vue >2000 l.** : `SeanceView` 3521, `StatsView` 2639, `DashboardView` 2540, `NutritionView` 1727. Splitter en subviews séparées.
- [ ] **CODE-5 — `RestTimerManager` défini dans `SeanceView`** : extraire dans `Services/RestTimerManager.swift`.
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

- [x] Dashboard 16 UX fixes : reorder TodayCard, skeleton loading, NavigationLinks, font WeekGrid, DeloadChip level 1, MoodCard, HeatmapView retiré, GreatDayCard badge intégré, PeakPrediction CTA, sleep prompt label, RecoverySnapshot indigo (2026-03-29)
- [x] Progressive overload — RIR capture, RPE gradué, détection chute de performance, trend 4 semaines (2026-03-26)
- [x] StatsView 5 onglets, period picker, smart insights (2026-03-26)
- [x] IntelligenceView contexte enrichi, NarrativeCard, Ghost Mode (2026-03-26)
- [x] Peak Prediction 7j dashboard (2026-03-26)
- [x] PR detection + notification locale iOS
- [x] CRUD complet inventaire
- [x] Checklist "Avant de partir" sur dashboard
