# TrainingOS — TODO & Améliorations

> Tour de l'app réalisé le 2026-03-15. Classé par priorité réelle (impact utilisateur).

---

## 🔴 CRITIQUE — Bugs visibles / corruption de données

- [x] **409 guard + SyncManager requeue** : `SyncManager` traite déjà 409 comme succès (`|| code == 409`) → pas de requeue. `offlinePost()` ne queue que sur erreur réseau (URLError), jamais sur 4xx. Confirmé correct.
- [x] **Cache stale après log séance** : `APIService.logExercise()` invalide maintenant `seance_data` + `dashboard` immédiatement après chaque log.
- [x] **Désync timezone client/serveur** : supprimé `localToday` (recalcul depuis timezone iPhone) dans `DashboardData` et `SeanceData`. Toutes les vues utilisent `today` (fourni par le serveur en heure MTL).

---

## 🟠 HAUTE PRIORITÉ — UX bloquante

- [ ] **Edit session dans Historique** : on peut supprimer mais pas modifier (RPE, commentaire, exercices). Faut tout supprimer et re-logger → friction énorme. Ajouter un sheet d'édition rapide.
- [x] **Validation reps dans SeanceView** : champ reps rouge + bordure rouge si valeur non numérique saisie (2026-03-29).
- [x] **Config Timer persistée** : workSecs/restSecs/prepareSecs/totalRounds sauvegardés via @AppStorage (2026-03-29).
- [ ] **Timer se stoppe en arrière-plan** : si l'app passe en background pendant le timer, il s'arrête. Utiliser `UNUserNotificationCenter` pour planifier des notifications à chaque phase (work/rest/done).
- [ ] **Validation photo profil** : aucune limite de taille sur l'upload photo → risque de timeout Vercel ou crash. Compresser/resizer avant envoi (max 500KB).

---

## 🟡 MOYENNE PRIORITÉ — Qualité & cohérence

- [ ] **Pas de pagination dans Historique** : toutes les séances sont chargées d'un coup. Implémenter une pagination (20 items + "Charger plus").
- [ ] **Pas de filtre par date dans Historique** : impossible de chercher "séances de février". Ajouter un picker mois/année.
- [x] **1RM formula ignore RPE** : `w × (1 + reps/30)` surestime si les reps étaient à faible effort. → Résolu partiellement via RIR : quand avg_rir disponible, RPE implicite = 10−rir, modifie la suggestion de poids. 1RM Epley reste comme base de comparaison PR.
- [ ] **Deload recommandé mais pas auto-appliqué** : la bannière suggère un deload mais l'utilisateur doit manuellement baisser les poids. Ajouter un bouton "Appliquer le déload (−10%)" qui pré-remplit les charges.
- [x] **CacheService TTL** : TTL par endpoint (dashboard=5min, seance=5min, stats=15min, programme=1h, etc.) avec sidecar .expiry (2026-03-29).
- [x] **Programme : message si séance vide** : placeholder "Aucun exercice — tape + pour en ajouter" dans EditableSeanceProgramCard (2026-03-29).
- [x] **Nutrition : édition d'entrée** : bouton crayon sur chaque entrée + EditNutritionSheet + endpoint /api/nutrition/edit (2026-03-29).
- [x] **Objectifs : animation achievement** : sparkles + scale spring au appear quand obj.achieved (2026-03-29).
- [ ] **Goals sans deadline enforcement** : la deadline est affichée mais pas rappelée. Ajouter une notification locale J-7 et J-1 avant deadline d'un objectif.
- [ ] **Pas d'indication "exo jamais utilisé" dans inventaire** : des centaines d'exos ExerciseDB ne sont jamais utilisés dans le programme. Ajouter un badge ou tri "En programme / Jamais utilisé".
- [ ] **HIIT : pas de templates favoris** : reconfigurer chaque HIIT (rounds, work, rest) à chaque fois. Ajouter des configs sauvegardables.
- [ ] **HealthKit auto-import cardio/recovery** : fréquence cardiaque au repos, steps, et workouts importés manuellement seulement. Ajouter un auto-sync au lancement ou pull-to-refresh.
- [ ] **Pas d'export données** : aucun moyen de télécharger ses données (CSV/JSON). Ajouter un bouton "Exporter mes données" dans le profil.

---

## 🟢 BASSE PRIORITÉ — Améliorations UX

- [ ] **SeanceView : log set-by-set** : actuellement on log "100kg 5,5,5,5" mais pas set par set en temps réel. Ajouter une option "mode set-by-set" qui incrémente automatiquement après chaque set.
- [ ] **Programme : message si séance vide** : si une séance n'a aucun exercice, afficher "Aucun exercice — tape + pour en ajouter" au lieu d'un badge vide.
- [ ] **Intelligence : historique conversations** : les propositions IA disparaissent après fermeture. Sauvegarder l'historique des conversations du coach local.
- [ ] **Mood : corrélation avec performance** : le mood est loggé mais jamais croisé avec les stats d'entraînement. Ajouter un graphe "humeur vs RPE" dans MentalHealthView ou StatsView.
- [ ] **HIIT vs Muscu sur même vue** : dans Historique, les 2 tabs sont séparés mais une journée peut contenir les deux. Ajouter une vue "Timeline" qui merge tout par date.
- [ ] **Heatmap HIIT distinct de muscu** : la heatmap 30 jours traite identiquement une séance HIIT et une séance muscu. Utiliser une couleur différente (ex: bleu pour HIIT, orange pour muscu).
- [ ] **Injury tracking** : aucun moyen de logger une douleur/blessure et d'en tenir compte dans les suggestions. Ajouter un champ optionnel "zone douloureuse" dans le log séance.
- [ ] **Pas de badge achèvement objectif** : quand un objectif est atteint, rien ne se passe visuellement. Ajouter une animation/confetti + archivage automatique.

---

## 🏗️ ARCHITECTURE / TECHNIQUE

- [ ] **CacheService sans TTL** : le cache disque peut servir des données vieilles de semaines si réseau absent. Ajouter un TTL par endpoint (ex: `dashboard` = 5min, `programme_data` = 1h).
- [ ] **Pas de suite de tests E2E** : les tests pytest couvrent le backend mais pas les chemins critiques iOS (log + cache + sync). Considérer XCUITest pour les flows principaux.
- [ ] **API sans documentation** : aucun Swagger/OpenAPI. Documenter les endpoints principaux dans `ai/AGENT_CONTEXT.md` ou un fichier `api/README.md`.

---

## 🌙 EN COURS — Séance du Soir

- [ ] **Étape 1** — Migration Supabase : colonne `slot` sur `weekly_schedule`, UNIQUE(day_name, slot)
- [ ] **Étape 2** — db.py : `get/set_evening_week_schedule`, `get_or_create_workout_session_second`, filtre `slot='morning'`
- [ ] **Étape 3** — planner.py : `get_evening_schedule`, `get_today_evening`
- [ ] **Étape 4** — index.py : `/api/seance_soir_data`, `/api/evening_schedule`, `is_second` sur `/api/log`
- [ ] **Étape 5** — APIModels.swift : `SeanceSoirData`, memberwise init sur `SeanceData`
- [ ] **Étape 6** — APIService.swift : `fetchSeanceSoirData`, `logExerciseEvening`
- [ ] **Étape 7** — SeanceSoirView.swift (nouveau) : `SeanceSoirViewModel` + `SeanceSoirView`
- [ ] **Étape 8** — DashboardView.swift : `SoirCardView` sous `TodayCardView`
- [ ] **Étape 9** — ProgrammeView.swift : section config schedule du soir

---

## ✅ Déjà résolu récemment

- [x] **Progressive overload — RIR capture** : champ RIR par set (stepper 0–6), envoyé à l'API, stocké en JSONB, utilisé comme fallback RPE dans suggest_next_weight (2026-03-26)
- [x] **Progressive overload — RPE gradué** : remplacement des seuils binaires par 5 niveaux (±full, ±half, maintain) dans `progression.py` (2026-03-26)
- [x] **Progressive overload — chute de performance** : `detect_performance_drop()` dans `deload.py`, déclenche déload si 1RM chute ≥10% sur 3 sessions (2026-03-26)
- [x] **Progressive overload — trend 4 semaines** : `compute_progression_rate()` via régression linéaire 28j, nudge +demi-incrément si trend ≤0 en zone maintain (2026-03-26)
- [x] **StatsView refactor** : 5 onglets (Volume, 1RM, Groupes, Cardio, Corps), period picker, smart insights auto-générés (2026-03-26)
- [x] **IntelligenceView — optimisation données** : réutilise cache `stats_data`, contexte athlete enrichi (LSS, ACWR, poids, muscles), format terse −50% tokens (2026-03-26)
- [x] **Ghost Mode** : bannière dans SeanceView avec meilleure session historique + barre de progression volume en temps réel (2026-03-26)
- [x] **Pre-Brief enrichi** : MorningBriefCardView avec sparkline LSS 7j, readiness delta, heures depuis dernière séance (2026-03-26)
- [x] **Narrative hebdomadaire** : NarrativeCard dans IntelligenceView (Claude ~150 mots style journaliste), cachée par semaine ISO (2026-03-26)
- [x] **Peak Prediction** : strip 7j dans Dashboard avec LSS prédit par régression + jour optimal mis en avant (2026-03-26)

- [x] Exercices ajoutés au programme → inventaire (timeout `save_inventory` fixé → `add_exercise` ciblé)
- [x] Limit 1000 rows PostgREST sur `get_exercises` → `.limit(10000)`
- [x] PR detection sur `/api/log` + notification push locale iOS
- [x] CRUD complet inventaire (add/edit/delete depuis InventaireView)
- [x] Remove programme → supprime inventaire si plus dans aucune séance
- [x] Programme dans navbar, Historique dans Plus
- [x] Checklist "Avant de partir" sur dashboard (mode compact/expand)
