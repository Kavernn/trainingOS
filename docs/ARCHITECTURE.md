# Architecture — TrainingOS

## Vue d'ensemble

TrainingOS est une **Progressive Web App (PWA)** d'entraînement personnel, déployée sur **Vercel** (serverless Python) et accessible nativement sur **iOS via Capacitor**.

```
Navigateur / iOS (Capacitor)
        │
        ▼
   Flask (Vercel Serverless)
        │
   ┌────┴────┐
   │  SQLite │  ◄── local dev / offline
   │Supabase │  ◄── prod / sync cloud
   └─────────┘
```

---

## Stack technique

| Couche       | Technologie                        |
|--------------|------------------------------------|
| Serveur      | Python · Flask 3.1                 |
| Templates    | Jinja2 (HTML server-rendered)      |
| Déploiement  | Vercel (serverless, `api/index.py`)|
| Base données | Supabase (PostgreSQL) + SQLite local|
| Mobile iOS   | Capacitor 6 (WKWebView natif)      |
| IA coach     | Anthropic Claude (Haiku/Sonnet)    |
| PWA          | Service Worker + Web App Manifest  |

---

## Structure des dossiers

```
trainingOS/
├── api/                    # Backend Python
│   ├── index.py            # Point d'entrée Flask + toutes les routes
│   ├── db.py               # Couche données (Supabase + SQLite, offline-first)
│   ├── flask_app.py        # Config Flask partagée
│   ├── planner.py          # Planification hebdomadaire
│   ├── sessions.py         # Gestion des séances
│   ├── log_workout.py      # Logging des exercices / poids
│   ├── progression.py      # Calcul 1RM, progression de charge
│   ├── hiit.py             # Séances HIIT
│   ├── nutrition.py        # Suivi nutritionnel / déficit calorique
│   ├── inventory.py        # Programme d'exercices (ex-inventaire)
│   ├── stats.py            # Statistiques & Personal Records
│   ├── goals.py            # Objectifs
│   ├── body_weight.py      # Suivi poids corporel
│   ├── deload.py           # Détection & gestion du déload
│   ├── user_profile.py     # Profil utilisateur
│   ├── timer.py            # Timer HIIT/repos
│   └── warmup.py           # Échauffement
│
├── templates/              # Jinja2 — UI server-rendered
│   ├── base.html           # Layout commun (nav, safe area iOS)
│   ├── index.html          # Dashboard principal
│   ├── seance.html         # Séance muscu en cours
│   ├── historique.html     # Historique par date
│   ├── planificateur.html  # Planning hebdomadaire
│   ├── stats.html          # Dashboard stats & PRs
│   ├── timer.html          # Timer HIIT
│   ├── nutrition.html      # Tracker nutritionnel
│   ├── intelligence.html   # Coach IA (Claude)
│   └── ...                 # bodycomp, objectifs, profil, xp, notes
│
├── static/                 # Assets statiques
│   ├── manifest.json       # PWA manifest
│   └── sw.js               # Service Worker (cache / offline)
│
├── mobile/
│   └── ios/                # Projet Xcode généré par Capacitor
│
├── tests/                  # Tests Python (pytest)
├── data/                   # Données de référence (exercices JSON)
├── www/                    # WebView Capacitor (index.html PWA)
├── capacitor.config.ts     # Config Capacitor (iOS)
├── vercel.json             # Config déploiement Vercel
├── requirements.txt        # Dépendances Python
└── package.json            # Dépendances Capacitor/npm
```

---

## Couche données — `api/db.py`

Système **offline-first** à double stockage :

| Mode       | Comportement                                           |
|------------|--------------------------------------------------------|
| `ONLINE`   | Lecture/écriture Supabase ; miroir SQLite local (clean)|
| `OFFLINE`  | SQLite uniquement (dirty=1 pour sync future)           |
| `HYBRID`   | Tente Supabase, fallback SQLite dirty                  |

- **Conflit** résolu par **Last-Write-Wins** via `updated_at` (ISO UTC)
- Sur **Vercel** : pas de SQLite (filesystem readonly) → Supabase uniquement
- `sync_now()` : pousse les entrées `dirty` locales vers Supabase au retour en ligne

Toutes les données sont stockées en **clé/valeur JSON** dans la table `kv` Supabase.

---

## Routes principales (`api/index.py`)

| Route                  | Description                        |
|------------------------|------------------------------------|
| `GET /`                | Dashboard                          |
| `GET/POST /seance`     | Séance muscu                       |
| `GET /historique`      | Historique des séances             |
| `GET/POST /planificateur` | Planning hebdo                  |
| `GET /stats`           | Statistiques & PRs                 |
| `GET /timer`           | Timer HIIT/repos                   |
| `GET/POST /nutrition`  | Tracker nutritionnel               |
| `GET/POST /intelligence` | Coach IA Claude                  |
| `GET/POST /profil`     | Profil utilisateur                 |
| `GET /xp`              | Système XP & progression           |

---

## PWA & iOS

- **Service Worker** (`static/sw.js`) : cache offline, auto-update à chaque déploiement Vercel via version hash
- **Manifest** (`static/manifest.json`) : icônes, splash, `display: standalone`, safe area
- **Capacitor 6** : encapsule la PWA dans une `WKWebView` native iOS
  - Plugins : `App`, `Haptics`, `Network`, `SplashScreen`, `StatusBar`
  - Build : `cap sync && cap run ios`

---

## IA Coach

- Modèle : **Claude Sonnet 4.6** (analyse programme & HIIT) / **Haiku** (réponses rapides)
- SDK : `anthropic>=0.40.0`
- Analyse : historique séances, progression 1RM, volume par groupe musculaire, suggestions déload/HIIT
