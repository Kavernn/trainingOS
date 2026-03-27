# État du projet — TrainingOS

Dernière mise à jour : 2026-03-26

---

## Architecture actuelle

**App iOS native SwiftUI** connectée à un **backend Flask/Vercel** + **Supabase**.
La version PWA/Capacitor a été abandonnée au profit d'une app Swift pure.

---

## Systèmes complétés

### Core entraînement
- Logging séances musculaires (exercices, séries, poids, RPE, RIR)
- Progression automatique des charges (1RM Epley, algorithme RPE gradué)
- Déload automatique (détection stagnation + fatigue RPE + chute de performance)
- Séances HIIT avec timer dédié (beeps, flash, presets)
- Séance du soir (second slot quotidien)
- Historique des séances par date
- Programme hebdomadaire (planificateur par jour)
- Inventaire des exercices (CRUD complet)

### Statistiques & progression
- StatsView 5 onglets : Volume / 1RM / Groupes musculaires / Cardio / Corps
- Period picker (7j / 30j / 90j / tout)
- Smart Insights (texte narratif auto-généré)
- Personal Records (PR detection + notification locale)
- Sparklines et graphiques Charts

### Coach IA (IntelligenceView)
- Propositions de séance (Claude Sonnet 4.6)
- Insights hebdomadaires
- Récit narratif de la semaine (NarrativeCard)
- Contexte athlete enrichi : LSS, ACWR, poids, groupes musculaires, sessions
- Contexte optimisé (~1400 chars, format terse)
- Cache narratif par semaine (clé `narrative_YYYY-WXX`)

### Dashboard & UX
- MorningBrief enrichi : LSS sparkline 7j, readiness delta, heures depuis dernière séance
- PeakPredictionCard : 7 jours avec LSS prédit, jour optimal mis en avant (orange)
- Ghost Mode (SeanceView) : bannière avec meilleure session historique + barre de progression volume
- Haptics sur toutes les actions importantes
- Confetti sur PR et complétion de séance
- Timer de repos auto-start après chaque log

### Santé & récupération
- Apple Watch sync (HealthKit → Supabase via WatchSyncService)
- Life Stress Score (LSS) : 5 composantes (sommeil, HRV, FC repos, stress, fatigue)
- ACWR (Acute:Chronic Workload Ratio)
- RecoveryView (sommeil, FC repos, HRV, douleurs musculaires)
- BodyCompView (poids corporel + tendance)
- CardioView (log course, vélo, natation)
- SleepView
- MentalHealth suite (mood, journal, breathwork, PSS, self-care)
- HealthDashboard agrégé

### Infrastructure
- Offline-first : SyncManager (SwiftData → retry queue) + Supabase
- CacheService (TTL disque par clé)
- NetworkMonitor (NWPathMonitor)
- UnitSettings (kg/lbs, km/mi)

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

## En cours / Prochaines étapes

1. Tests automatisés élargis (couverture iOS SeanceView + progression logic)
2. Edit session inline dans Historique (sheet d'édition RPE/commentaire/exercices)
3. Background timer (UNUserNotificationCenter) pour séances HIIT
4. Pagination Historique (20 items + "Charger plus")

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
