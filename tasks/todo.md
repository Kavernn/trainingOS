# TrainingOS — TODO & Améliorations

> Tour de l'app réalisé le 2026-03-15. Mis à jour le 2026-03-29.

---

## 🔴 CRITIQUE — Bugs visibles / corruption de données

- [x] **409 guard + SyncManager requeue** : `SyncManager` traite déjà 409 comme succès (`|| code == 409`) → pas de requeue. `offlinePost()` ne queue que sur erreur réseau (URLError), jamais sur 4xx. Confirmé correct.
- [x] **Cache stale après log séance** : `APIService.logExercise()` invalide maintenant `seance_data` + `dashboard` immédiatement après chaque log.
- [x] **Désync timezone client/serveur** : supprimé `localToday` (recalcul depuis timezone iPhone) dans `DashboardData` et `SeanceData`. Toutes les vues utilisent `today` (fourni par le serveur en heure MTL).
- [x] **TodayCard affiche "Commencer" malgré séance loggée** : `if isLoggedToday, let session` échouait quand `alreadyLoggedToday=true` mais `sessions[todayDate]=nil` (désync cache). Séparé en deux conditions indépendantes (2026-03-29).
- [x] **Schema Supabase manquant `session_type`** : colonne `session_type` absente de `workout_sessions` bloquait le pipeline Séance du Soir. Migration 003 créée (2026-03-29).

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

---

## 🟢 BASSE PRIORITÉ — Améliorations UX

- [x] **SeanceView : log set-by-set** : bouton ➜ dans l'en-tête des sets, mode set-by-set avec highlight + bouton ✓ par set, auto-log quand dernier set confirmé (2026-03-29).
- [x] **Intelligence : historique conversations** : `ChatMessage` Codable, `@AppStorage("intelligence_history")`, restore au `.task`, save à `onChange(of: messages)` (2026-03-29).
- [x] **Mood : corrélation avec performance** : `MoodRPECorrelationCard` scatter chart + Pearson r dans `MoodTrackerView` (2026-03-29).
- [x] **HIIT vs Muscu sur même vue** : 3e tab "Timeline" dans `HistoriqueView`, `buildTimeline()` merge muscu+HIIT par date, `TimelineRow` (2026-03-29).
- [ ] **Heatmap HIIT distinct de muscu** : la heatmap 30 jours traite identiquement une séance HIIT et une séance muscu. Utiliser une couleur différente (ex: bleu pour HIIT, orange pour muscu). (Note: HeatmapView retirée du Dashboard → considérer dans StatsView.)
- [x] **Injury tracking** : champ "Zone douloureuse" optionnel dans `ExerciseCard`, transmis via `pain_zone` dans payload `/api/log`, stocké dans `history_entry` (2026-03-29).
- [x] **Pas de badge achèvement objectif** : sections Active/Atteints/Archivés dans `ObjectifsView`, bouton "Archiver" sur goals atteints, endpoint `/api/archive_objectif` + KV `goals_archived` (2026-03-29).

---

## 🏗️ ARCHITECTURE / TECHNIQUE

- [ ] **Pas de suite de tests E2E** : les tests pytest couvrent le backend mais pas les chemins critiques iOS (log + cache + sync). Considérer XCUITest pour les flows principaux.
- [ ] **API sans documentation** : aucun Swagger/OpenAPI. Documenter les endpoints principaux dans `api/README.md`.
- [x] **Migration 003 appliquée sur Supabase** : `session_type` + backfill + contrainte UNIQUE(date, session_type) (2026-03-29).

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

## ✅ Déjà résolu récemment

- [x] Dashboard 16 UX fixes : reorder TodayCard, skeleton loading, NavigationLinks, font WeekGrid, DeloadChip level 1, MoodCard, HeatmapView retiré, GreatDayCard badge intégré, PeakPrediction CTA, sleep prompt label, RecoverySnapshot indigo (2026-03-29)
- [x] Progressive overload — RIR capture, RPE gradué, détection chute de performance, trend 4 semaines (2026-03-26)
- [x] StatsView 5 onglets, period picker, smart insights (2026-03-26)
- [x] IntelligenceView contexte enrichi, NarrativeCard, Ghost Mode (2026-03-26)
- [x] Peak Prediction 7j dashboard (2026-03-26)
- [x] PR detection + notification locale iOS
- [x] CRUD complet inventaire
- [x] Checklist "Avant de partir" sur dashboard
