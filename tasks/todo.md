# TrainingOS — TODO & Améliorations

> Tour de l'app réalisé le 2026-03-15. Mis à jour le 2026-04-05.
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
- [ ] **Rebuild iOS Xcode** : compiler tous les changements 2026-04-05 (smart goals, UX fixes, body comp lbs, set_goal fix).

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

## 🎨 UI/UX — Problèmes affectant l'expérience utilisateur (audit 2026-04-05)

> Extraits de l'audit senior. Classés par impact utilisateur perçu.

- [ ] **#A6 — Flash données stale au refresh Dashboard** : le cache s'affiche 1–2s avant les données fraîches → l'UI "saute". Pull-to-refresh sans indicateur visible. **Fix** : skeleton loading pendant le fetch + `refreshable` qui montre un spinner.
- [ ] **#A8 — Erreurs réseau invisibles** : `try?` partout → liste vide sans message si ça plante. L'utilisateur pense que ses données ont disparu. Aucun bouton retry. **Fix** : `ErrorBannerView(error:onRetry:)` réutilisable + `catch` systématique dans chaque view qui fetche.
- [ ] **#A7 — Cache invalidation incohérente → doubles logs possibles** : log d'un exercice n'invalide pas `stats_data` ni `seance_soir_data`. L'utilisateur voit l'ancien volume dans Stats, pense que le log a raté, relogue → duplicate. **Fix** : map d'invalidation déclarative par action.
- [ ] **#A9 — Timezone mismatch → double log possible** : iOS utilise le fuseau local, le serveur utilise Montréal. À minuit heure locale hors MTL, `alreadyLogged` retourne false alors que la séance existe. **Fix** : iOS utilise toujours `today` fourni par le serveur, jamais `Date()` local.
- [ ] **#A10 — Scroll lent sur listes longues** : `ForEach` dans `VStack` dans NutritionView, HistoriqueView, InventaireView — toutes les cellules rendues même hors-écran. Freeze perceptible à 50+ items. **Fix** : `LazyVStack` partout où liste > 20 items. Remplacement 1:1.
- [ ] **#A13 — Spinners incohérents** : `ProgressView().tint(.orange)`, `.scaleEffect(1.3)`, `.tint(.white)` — variantes différentes dans 20+ views. **Fix** : composant `AppLoadingView` centralisé dans `Components/`.
- [ ] **États vides manquants** : certaines views affichent une page blanche si le fetch retourne vide (sans distinction "pas de données" vs "erreur réseau"). **Fix** : systématiser `EmptyStateView(icon:message:action:)` réutilisable.
- [ ] **Pas de feedback sur les actions destructives** : suppressions (body weight, entrée nutrition, exercice) avec confirmation dialog mais sans undo ni toast de confirmation. L'utilisateur n'est pas sûr que l'action a été exécutée.
- [ ] **Keyboard dismiss incohérent** : certains formulaires dismiss au tap hors champ, d'autres non. Pas de `@FocusState` ni de `scrollDismissesKeyboard` systématique.

---

## 🟢 BASSE PRIORITÉ — Améliorations UX

- [x] **SeanceView : log set-by-set** : bouton ➜ dans l'en-tête des sets, mode set-by-set avec highlight + bouton ✓ par set, auto-log quand dernier set confirmé (2026-03-29).
- [x] **Intelligence : historique conversations** : `ChatMessage` Codable, `@AppStorage("intelligence_history")`, restore au `.task`, save à `onChange(of: messages)` (2026-03-29).
- [x] **Mood : corrélation avec performance** : `MoodRPECorrelationCard` scatter chart + Pearson r dans `MoodTrackerView` (2026-03-29).
- [x] **HIIT vs Muscu sur même vue** : 3e tab "Timeline" dans `HistoriqueView`, `buildTimeline()` merge muscu+HIIT par date, `TimelineRow` (2026-03-29).
- [ ] **Heatmap HIIT distinct de muscu** : la heatmap 30 jours traite identiquement une séance HIIT et une séance muscu. Utiliser une couleur différente (ex: bleu pour HIIT, orange pour muscu). (Note: HeatmapView retirée du Dashboard → considérer dans StatsView.)
- [x] **Injury tracking** : champ "Zone douloureuse" optionnel dans `ExerciseCard`, transmis via `pain_zone` dans payload `/api/log`, stocké dans `history_entry` (2026-03-29).
- [x] **Pas de badge achèvement objectif** : sections Active/Atteints/Archivés dans `ObjectifsView`, bouton "Archiver" sur goals atteints, endpoint `/api/archive_objectif` + KV `goals_archived` (2026-03-29).
- [ ] **Profile non rempli** : name, age, goal, height, level, sex, weight tous null. UX : forcer l'onboarding ou afficher un prompt "Complète ton profil".
- [x] **Objectifs vides** : Smart Goals system implémenté — 7 types calculés automatiquement (2026-04-05).
- [ ] **Nutrition : cibles glucides/lipides = 0** : saisir les objectifs macro dans les settings.
- [ ] **Smart Goals — types avancés** : 1RM estimé, pace cardio, distance mensuelle, FC repos, PSS moyen, streak sommeil.

---

## 🏗️ ARCHITECTURE / TECHNIQUE

- [ ] **Pas de suite de tests E2E** : les tests pytest couvrent le backend mais pas les chemins critiques iOS (log + cache + sync). Considérer XCUITest pour les flows principaux.
- [ ] **API sans documentation** : aucun Swagger/OpenAPI. Documenter les endpoints principaux dans `api/README.md`.
- [x] **Migration 003 appliquée sur Supabase** : `session_type` + backfill + contrainte UNIQUE(date, session_type) (2026-03-29).
- [x] **Migration KV → relational complète** : table `kv` supprimée, toutes les données migrées vers tables relationnelles. Migration 011 appliquée. (2026-04-04).

---

## 🔐 AUDIT SENIOR — Sécurité & Architecture (2026-04-05)

> Issu de l'audit complet codebase. Priorisé du plus critique au plus mineur.
> Ne pas implémenter sans validation des priorités.

### 🔴 Critique

- [ ] **#A1 — Zéro authentification API** : 124 routes Flask accessibles sans token. N'importe qui connaissant l'URL Vercel peut lire/écrire/supprimer toutes les données. **Fix** : API key statique en header `Authorization: Bearer <token>` côté Flask (middleware) + `xcconfig` côté iOS. 1 journée de travail.

- [ ] **#A2 — `index.py` fichier dieu (3 060 lignes)** : routes, helpers, logique IA, nutrition, body comp, objectifs — tout mélangé. Impossible à maintenir, cold start Vercel ralenti, tests impossibles à isoler. **Fix** : Flask Blueprints — `api/routes/workout.py`, `api/routes/nutrition.py`, `api/routes/body_comp.py`, etc. `index.py` → 50 lignes d'app factory. Même traitement pour `db.py` (2 654 lignes). 2 jours.

- [ ] **#A3 — Exceptions silencieuses qui exposent les internals** : `except Exception as e: return jsonify({"error": str(e)}), 500` répété dans tout `index.py`. Envoie tracebacks Python bruts au client iOS (noms de tables, chemins, data partielle). **Fix** : handler global `@app.errorhandler(Exception)`, loggue le traceback serveur, renvoie message générique au client. `except (ValueError, KeyError)` pour erreurs prévisibles.

- [ ] **#A4 — `SeanceView.swift` monolithe (3 550 lignes, 93 state decorators)** : état partagé de façon incohérente entre ViewModel (7 `@Published`) et subviews (dizaines de `@State` locaux). Quand `ExerciseCard` modifie `@State weight`, le ViewModel ne le sait pas jusqu'au tap "Log" → risque de perte de données. **Fix** : `ExerciseViewModel` par exercice, `SeanceView` = orchestrateur pur, chaque composant < 400 lignes.

- [ ] **#A5 — Pas de source de vérité unique** : `DashboardView` a 12 `@State` vars. Données partagées (profil, unités, today) recalculées dans chaque view. `@AppStorage` peut contenir des données obsolètes qui divergent du serveur. **Fix** : `AppState` global `@Observable` injecté via `@Environment`. Les views observent, ne possèdent pas.

### 🟠 Haute priorité

- [ ] **#A6 — Flash de données stale au refresh Dashboard** : cache affiché immédiatement, puis données fraîches remplacent → UI "saute" visuellement. Aucun indicateur pendant pull-to-refresh. **Fix** : skeleton loading systématique pendant fetch, ou marquer le cache stale après chaque mutation et re-fetch en background silencieux.

- [ ] **#A7 — Invalidation cache incohérente** : log d'un exercice invalide `seance_data` mais pas `seance_soir_data`, `stats_data`, `dashboard`. L'utilisateur voit l'ancien volume dans Stats après avoir loggé → pense que le log a raté → relogue → duplicate. **Fix** : map d'invalidation déclarative `{ "log_exercise": ["seance_data", "dashboard", "stats_data", ...] }`. Fonction `invalidate(trigger:)` appelée après chaque mutation.

- [ ] **#A8 — Erreurs réseau invisibles dans la majorité des views** : `try?` partout dans les views iOS. Si un appel échoue, la liste reste vide sans message. L'utilisateur ne sait pas si c'est un bug ou des données vraiment vides. Pas de bouton retry. **Fix** : `@State private var error: Error?` + `catch { self.error = error }` systématique. Composant `ErrorBannerView(error:onRetry:)` réutilisable.

- [ ] **#A9 — Mismatch timezone iOS (local) vs backend (Montréal)** : iOS calcule `today` avec le fuseau de l'iPhone. Si l'utilisateur est à +6h, à minuit heure locale = "demain" pour iOS, "hier soir" pour le serveur → `alreadyLogged` retourne false → double log possible. **Fix** : le serveur envoie `today: "YYYY-MM-DD"` dans chaque réponse (déjà dans `DashboardData`). iOS utilise TOUJOURS ce `today` serveur pour toutes les comparaisons. Jamais `Date()` côté client pour "est-ce aujourd'hui ?".

- [ ] **#A10 — `ForEach` dans `VStack` sur listes longues** : NutritionView, HistoriqueView, InventaireView rendent toutes les cellules même hors-écran. Scroll freeze perceptible dès 50+ items sur iPhone SE. **Fix** : `LazyVStack` partout où la liste peut dépasser 20 items. Remplacement 1:1, 30 secondes par view.

### 🟡 Qualité & cohérence

- [ ] **#A11 — `DateFormatter` recréé inline partout (3+ variantes)** : `DashboardView`, `ObjectifsView`, `HistoriqueView`, `BodyCompView` — chacun instancie son propre `DateFormatter()` avec locales parfois différentes (`fr_CA` vs rien). `DateFormatter` est coûteux à créer. **Fix** : `extension DateFormatter { static let isoDate: DateFormatter = { ... }() }` — singletons statiques lazy partagés.

- [ ] **#A12 — Logique métier dans les Views** : `DashboardView` fait 8 appels réseau dans `.task {}`. `NutritionView` parse du JSON à la main. Impossible à tester unitairement, impossible de faire des SwiftUI previews avec données mockées. **Fix** : un ViewModel par view complexe. La View n'observe que, n'agit pas.

- [ ] **#A13 — Pas de composant de loading uniforme** : `ProgressView().tint(.orange)`, `.scaleEffect(1.3)`, `.tint(.white).scaleEffect(0.8)` — variations ad-hoc dans 20+ views. **Fix** : `struct AppLoadingView: View` dans `Components/`. Une ligne à changer pour tout mettre à jour.

- [ ] **#A14 — Parsing JSON manuel dans NutritionView** : `JSONSerialization.jsonObject` + casts `as? [[String: Any]]` + `d["quantity"] as? Double` — 50 lignes qui retournent des données partielles silencieusement si un champ manque. **Fix** : `struct NutritionEntry: Codable`. `try JSONDecoder().decode([NutritionEntry].self, from: data)`. 5 lignes typesafe.

- [ ] **#A15 — `APIModels.swift` monolithe (1 252 lignes, 35+ structs)** : tous les modèles iOS dans un fichier. Compile-time plus long, merge conflicts systématiques. **Fix** : un fichier par domaine — `Models/Workout.swift`, `Models/Nutrition.swift`, `Models/BodyComp.swift`, etc.

- [ ] **#A16 — Unités sans contrat documenté entre iOS et backend** : `body_weight_logs.weight` stocke des lbs mais rien ne le documente en DB. Dans 6 mois on stocke accidentellement en kg — les valeurs restent plausibles (85 vs 189), la corruption est silencieuse. **Fix** : commentaire `-- unit: lbs` sur chaque colonne weight dans `docs/schema.sql` + dans les fonctions `db.py` qui les manipulent.

### 🟢 Mineur

- [ ] **#A17 — `START_DATE = date(2026, 3, 3)` hardcodé** : baseline du compteur de semaines dans `index.py`. Devrait être `user.created_at` depuis la DB.

- [ ] **#A18 — Pas de SwiftUI previews** : aucun `#Preview` dans les views complexes. Impossible de développer sans lancer l'app sur device. Bloque la rapidité de développement UI.

- [ ] **#A19 — Photos de profil en base64 dans JSON** : une photo 500KB = 666KB qui transite à chaque fetch du profil. **Fix** : URL vers Supabase Storage bucket, chargement lazy avec `AsyncImage`.

- [ ] **#A20 — Rate limiting IA non thread-safe en prod** : token bucket manuel avec `threading.Lock()`. Sur Vercel multi-workers, chaque worker a son propre état → rate limit contournable. **Fix** : compteur dans Supabase ou cache Redis partagé entre workers.

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

## ✅ Déjà résolu récemment

- [x] Dashboard 16 UX fixes : reorder TodayCard, skeleton loading, NavigationLinks, font WeekGrid, DeloadChip level 1, MoodCard, HeatmapView retiré, GreatDayCard badge intégré, PeakPrediction CTA, sleep prompt label, RecoverySnapshot indigo (2026-03-29)
- [x] Progressive overload — RIR capture, RPE gradué, détection chute de performance, trend 4 semaines (2026-03-26)
- [x] StatsView 5 onglets, period picker, smart insights (2026-03-26)
- [x] IntelligenceView contexte enrichi, NarrativeCard, Ghost Mode (2026-03-26)
- [x] Peak Prediction 7j dashboard (2026-03-26)
- [x] PR detection + notification locale iOS
- [x] CRUD complet inventaire
- [x] Checklist "Avant de partir" sur dashboard
