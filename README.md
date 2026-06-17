# TrainingOS — Native SwiftUI App

Application iOS native de tracking fitness/santé connectée à un backend Flask déployé sur Vercel + Supabase.

---

## Setup Xcode

1. Ouvrir `TrainingOS.xcodeproj`
2. Signer avec ton Apple Developer account (Signing & Capabilities)
3. Activer **HealthKit** dans les capabilities
4. Build & Run sur device physique (HealthKit ne fonctionne pas sur simulateur)

### Variables d'environnement (backend)

| Variable | Description |
|---|---|
| `SUPABASE_URL` | URL du projet Supabase |
| `SUPABASE_KEY` | Clé service role Supabase |
| `SECRET_KEY` | Clé Flask sessions |
| `ANTHROPIC_API_KEY` | Pour les routes IA (coach, planner) |
| `X_RAPIDAPI_KEY` | Optionnel — API nutrition externe |

---

## Architecture

Voir `docs/ARCHITECTURE.md` pour la description complète (stack, algorithmes, flow données).

Structure haut niveau : `Views/` (20+ dossiers) · `Services/` (APIService + 20 extensions) · `Utilities/AppTheme.swift` (10 thèmes) · `api/routes/` (78 blueprints Flask).

---

## Backend (`api/`)

Flask déployé sur **Vercel** (serverless), base de données **Supabase** (PostgreSQL).

Déployé sur Vercel (serverless). 78 blueprints dans `api/routes/`, engines analytiques dans `api/*_engine.py`. Voir `api/README.md` pour la liste des endpoints.

### Flow Apple Watch → Supabase

```
Apple Watch
  └── HealthKit (iPhone)
        └── HealthKitService.fetchTodayHealthSnapshot()
              └── WatchSyncService.sync()
                    └── APIService.syncWearableData()
                          └── POST /api/wearable/sync
                                ├── recovery_logs  (steps, sleep, RHR, HRV, active energy)
                                ├── cardio_logs    (workouts du jour)
                                └── body_weight_logs (poids + % gras si absent)
```

**Déclencheurs sync :**
| Trigger | Fréquence |
|---|---|
| App launch | 1× au démarrage |
| App foreground (`scenePhase == .active`) | Si > 5 min depuis dernier refresh |
| Background HealthKit observers | ~toutes les heures |
| Ouverture RecoveryView | Si > 30 min depuis dernière sync |
| Bouton refresh manuel (RecoveryView) | À la demande |

---

## Base de données (Supabase)

Schéma complet : `docs/schema.sql` (migrations 001-047 intégrées).
Migrations 048-072 : appliquer les fichiers `docs/migrations/0NN_*.sql` dans l'ordre.
≥54 tables — voir `docs/SCHEMA_TRUE_STATE.md` pour le détail.

---

## Docs

| Fichier | Contenu |
|---|---|
| `docs/ARCHITECTURE.md` | Stack, algorithmes ACWR/progression/deload, flow données |
| `docs/CONVENTIONS.md` | Sources de vérité, lbs, e1RM, soft-delete, no-fallback |
| `docs/THEMING.md` | 10 thèmes, tokens sémantiques, carve-outs mood |
| `docs/DECISIONS.md` | ADRs datés |
| `docs/STATE.md` | Changelog des fonctionnalités |
| `docs/SCHEMA_TRUE_STATE.md` | Tables DB, migrations appliquées |
| `docs/DATA_INTEGRITY_AUDIT.md` | Règles CRUD Supabase |
| `tasks/lessons.md` | Pièges connus et patterns validés |
