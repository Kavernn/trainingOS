# TrainingOS — TODO & Améliorations

> Tour de l'app réalisé le 2026-03-15. Classé par priorité réelle (impact utilisateur).

---

## 🔴 CRITIQUE — Bugs visibles / corruption de données

- [ ] **409 guard + SyncManager requeue** : quand `/api/log` retourne 409 ("already_logged"), le `SyncManager` requeue quand même le payload → risque de double-log. iOS doit parser 409 et bloquer le retry.
- [ ] **Cache stale après log séance** : après avoir loggé un exercice, `SeanceView` peut toujours afficher "pas loggé" si le cache n'est pas invalidé immédiatement. `DashboardView` a le même problème avec `alreadyLoggedToday`. Invalider le cache `seance_data` + `dashboard` immédiatement après chaque log.
- [ ] **Désync timezone client/serveur** : le backend calcule `today_date` en heure de Montréal, le client recompute la date en heure locale iPhone. Si l'utilisateur voyage (ex: PST), les logs peuvent atterrir sur le mauvais jour.

---

## 🟠 HAUTE PRIORITÉ — UX bloquante

- [ ] **Edit session dans Historique** : on peut supprimer mais pas modifier (RPE, commentaire, exercices). Faut tout supprimer et re-logger → friction énorme. Ajouter un sheet d'édition rapide.
- [ ] **Pas de helper format reps dans SeanceView** : le champ reps accepte "5,5,5,5" mais aussi "abc" → afficher un exemple sous le champ ("ex: 5,5,5,4") et rejeter les formats invalides côté iOS avant envoi.
- [ ] **Pas de config sauvegardée dans Timer** : l'utilisateur re-configure work/rest/rounds à chaque séance. Ajouter des presets sauvegardables (ex: "Tabata 20/10 x8").
- [ ] **Timer se stoppe en arrière-plan** : si l'app passe en background pendant le timer, il s'arrête. Utiliser `UNUserNotificationCenter` pour planifier des notifications à chaque phase (work/rest/done).
- [ ] **Validation photo profil** : aucune limite de taille sur l'upload photo → risque de timeout Vercel ou crash. Compresser/resizer avant envoi (max 500KB).

---

## 🟡 MOYENNE PRIORITÉ — Qualité & cohérence

- [ ] **Pas de pagination dans Historique** : toutes les séances sont chargées d'un coup. Implémenter une pagination (20 items + "Charger plus").
- [ ] **Pas de filtre par date dans Historique** : impossible de chercher "séances de février". Ajouter un picker mois/année.
- [ ] **1RM formula ignore RPE** : `w × (1 + reps/30)` surestime si les reps étaient à faible effort. Ajouter un facteur RPE dans le calcul (Brzycki ajusté).
- [ ] **Deload recommandé mais pas auto-appliqué** : la bannière suggère un deload mais l'utilisateur doit manuellement baisser les poids. Ajouter un bouton "Appliquer le déload (−10%)" qui pré-remplit les charges.
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

## ✅ Déjà résolu récemment

- [x] Exercices ajoutés au programme → inventaire (timeout `save_inventory` fixé → `add_exercise` ciblé)
- [x] Limit 1000 rows PostgREST sur `get_exercises` → `.limit(10000)`
- [x] PR detection sur `/api/log` + notification push locale iOS
- [x] CRUD complet inventaire (add/edit/delete depuis InventaireView)
- [x] Remove programme → supprime inventaire si plus dans aucune séance
- [x] Programme dans navbar, Historique dans Plus
- [x] Checklist "Avant de partir" sur dashboard (mode compact/expand)
