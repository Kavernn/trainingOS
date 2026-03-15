# Tâches — TrainingOS

Les agents sélectionnent et implémentent les tâches de cette liste.
Mettre à jour ce fichier et `STATE.md` après chaque tâche complétée.

---

## Haute priorité

- [x] Logger les appels Claude (remplacer les `print` DEBUG par un vrai logger)
- [x] Forcer `SECRET_KEY` en production (lever une erreur si valeur par défaut détectée sur Vercel)
- [x] Ajouter un rate limiting sur les appels à l'API Anthropic (éviter dépassement de coût)
- [x] Tests Flask pour les routes principales (seance_data, historique_data, log, deload_status)
- [x] Gestion erreur offline côté UI iOS — toast capsule en bas via SyncManager.offlineToast, auto-dismiss 3.5s, app-wide via ContentView

---

## Priorité moyenne — Robustesse

- [x] Indicateur UI de sync offline (endpoint /api/sync_status exposant le nombre de dirty)
- [x] Externaliser le CSS inline volumineux des templates vers `static/` (base.html → main.css)
- [x] Améliorer la page `intelligence.html` : historique des échanges avec le coach IA
- [x] Déload automatique : endpoint `/api/deload_status` exposant stagnation + RPE + recommandation
- [x] Progression dynamique autorégulatée par RPE — remplacer la progression linéaire fixe de `progression.py` par une logique RPE-based : RPE ≤ 6 → augmente, RPE 7-8 → maintien, RPE ≥ 8.5 → réduit. Étendre au-delà des 7 exercices hardcodés pour couvrir tout l'inventaire dynamique
- [x] Pagination historique — `fetchJournalEntries`, `fetchMoodHistory`, `fetchSleepHistory` chargent tout en mémoire. Ajouter cursor-based pagination sur les endpoints et côté iOS
- [ ] Tests Swift — couvrir SeanceViewModel (restauration logResults), CacheService (TTL, fallback), SyncManager (flush, retry, purge) — nécessite création d'un target XCTest dans Xcode GUI

---

## Priorité moyenne — Innovation

- [x] ACWR (Acute:Chronic Workload Ratio) — calcul 7j/28j de volume à partir de `v_session_volume`. Exposer `/api/acwr` avec ratio + zone (sous-charge / optimal / surcharge / danger). Visualiser dans StatsView. Prédit le risque de blessure avant qu'il se manifeste — absent de toutes les apps grand public
- [ ] Coaching proactif basé sur LSS + planning — au lieu de répondre passivement, le coach analyse chaque matin : LSS < 40 + séance lourde planifiée → propose automatiquement de décaler ou alléger. Endpoint `/api/coach/morning_brief` qui retourne une recommandation structurée
- [ ] Corrélations croisées personnalisées — croiser sommeil + HRV + 1RM + volume + mood sur les données réelles de l'utilisateur. Ex : "Quand tu dors < 7h, ton 1RM chute en moyenne de X% le lendemain". Endpoint `/api/insights/correlations` + vue dédiée dans Intelligence
- [ ] Détection PR en temps réel + notification — détecter un nouveau Personal Record au moment du log (`logExercise`) et déclencher une notification push locale iOS immédiatement pendant la séance

---

## Priorité basse / Long terme

- [ ] Partage de programme entre utilisateurs (export/import JSON)
- [ ] Notifications push PWA (rappels séance planifiée)
- [ ] Mode sombre
- [ ] Internationalisation (EN/FR)
- [ ] Widget iOS lockscreen — séance du jour + LSS du jour
- [ ] Complication Apple Watch — LSS + prochain exercice
- [ ] Auth multi-utilisateur — actuellement mono-user (usage personnel). Quand distribution envisagée : ajouter `user_id` sur toutes les tables, JWT entre iOS et Flask, RLS Supabase par utilisateur

---

## Complétées récemment

- [x] Tracker nutritionnel complet (calories, macros, déficit)
- [x] Historique par date avec édition inline
- [x] Coach IA migré vers Claude Sonnet 4.6
- [x] Safe area iOS + PWA manifest amélioré
- [x] Auto-update Service Worker sur déploiement Vercel
- [x] Responsive mobile sur toutes les pages
- [x] Fix calcul 1RM et propagation édition séance
- [x] Fix décalage UTC/heure locale pour le log des séances
- [x] Timer HIIT : beeps, flash, options panel
- [x] Statistiques : KPIs globaux + Personal Records
- [x] Schéma relationnel PostgreSQL (25 tables, 3 vues analytiques)
- [x] Migration KV → tables relationnelles (1417 lignes migrées)
- [x] Couche domaine db.py (30+ méthodes avec fallback KV)
- [x] Offline-first iOS : SwiftData + PendingMutation + SyncManager outbox
- [x] offlinePost() — toutes les mutations iOS passent par l'outbox
