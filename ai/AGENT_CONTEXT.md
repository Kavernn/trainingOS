# AI Agent Context — TrainingOS

Ce fichier fournit le contexte opérationnel pour les agents IA travaillant sur ce dépôt.
Lire ce fichier avant toute modification.

---

# Vue d'ensemble du projet

**TrainingOS** est une Progressive Web App (PWA) d'entraînement personnel, déployée en serverless sur Vercel et accessible nativement sur iOS via Capacitor.

Fonctionnalités principales :

* planification hebdomadaire des séances
* logging des exercices et suivi de progression (1RM, charges)
* séances HIIT avec timer dédié
* suivi nutritionnel et déficit calorique
* historique et statistiques (Personal Records, volume)
* coach IA (Claude Haiku/Sonnet) pour suggestions de programme et déload
* objectifs, suivi poids corporel, composition corporelle
* mode offline-first avec sync Supabase

---

# Stack technique

Backend

* Python 3
* Flask 3.1 (server-rendered via Jinja2)
* Déployé sur Vercel (serverless, point d'entrée : `api/index.py`)

Base de données

* Supabase (PostgreSQL) — production
* SQLite local (`.local_kv.db`) — dev / offline / cache
* Stockage clé/valeur JSON (table `kv`)

Mobile

* Capacitor 6 (WKWebView iOS natif)
* PWA : Service Worker + Web App Manifest

IA

* Anthropic Claude — SDK `anthropic>=0.40.0`
* Modèles : Sonnet 4.6 (analyse), Haiku (réponses rapides)

---

# Environnement de développement

Prérequis

* Python >= 3.10
* pip
* Node >= 18 (pour Capacitor/iOS uniquement)
* Xcode (pour build iOS)

Installation Python

```bash
pip install -r requirements.txt
```

Variables d'environnement (fichier `.env` à la racine)

```
SUPABASE_URL=...
SUPABASE_ANON_KEY=...
SECRET_KEY=...
ANTHROPIC_API_KEY=...
APP_DATA_MODE=HYBRID   # ONLINE | OFFLINE | HYBRID
```

Lancer en local

```bash
python api/index.py
# ou
flask --app api/index run --debug
```

URL locale : http://localhost:5000

---

# Opérations Capacitor / iOS

Synchroniser le projet web vers iOS

```bash
npm run sync        # cap sync
npm run ios         # cap run ios
npm run open:ios    # cap open ios (ouvre Xcode)
```

---

# Fichiers clés

| Fichier | Rôle |
|---|---|
| `api/index.py` | Point d'entrée Flask + toutes les routes HTTP |
| `api/db.py` | Couche données offline-first (Supabase + SQLite) |
| `api/planner.py` | Planning hebdomadaire |
| `api/progression.py` | Calcul 1RM, progression de charges |
| `api/nutrition.py` | Tracker nutritionnel |
| `api/sessions.py` | Gestion et log des séances |
| `api/intelligence.py` (route) | Coach IA Claude |
| `templates/base.html` | Layout commun (nav, safe area iOS) |
| `static/sw.js` | Service Worker PWA |
| `static/manifest.json` | PWA manifest |
| `capacitor.config.ts` | Config Capacitor iOS |
| `vercel.json` | Config déploiement Vercel |

---

# Structure du projet

```
trainingOS/
├── api/            # Backend Python (Flask + logique métier)
├── templates/      # HTML Jinja2 (UI server-rendered)
├── static/         # Assets, SW, manifest
├── mobile/ios/     # Projet Xcode généré par Capacitor
├── tests/          # Tests pytest
├── data/           # Données de référence (exercices JSON)
└── www/            # WebView Capacitor
```

---

# Architecture données — db.py

Stockage clé/valeur JSON en double couche :

| Mode | Comportement |
|---|---|
| `ONLINE` | Lecture/écriture Supabase ; miroir SQLite local (dirty=0) |
| `OFFLINE` | SQLite uniquement (dirty=1 pour sync future) |
| `HYBRID` | Tente Supabase, fallback SQLite dirty |

Conflit résolu par Last-Write-Wins via `updated_at` ISO UTC.
Sur Vercel : filesystem readonly → Supabase uniquement.

API publique : `get_json(key)`, `set_json(key, value)`, `update_json(key, patch)`, `append_json_list(key, entry)`, `sync_now()`

---

# Règles de code

* Ne jamais accéder à Supabase directement — toujours passer par `db.get_json` / `db.set_json`
* Les templates sont server-rendered : pas de framework JS frontend
* Le JS dans les templates doit rester vanilla (pas de React, pas de build step)
* Respecter la structure existante des routes dans `api/index.py`
* Ne jamais committer `.env`, clés API, credentials

---

# Règles UI

* Toutes les pages héritent de `templates/base.html`
* CSS inline dans les templates (pas de fichiers CSS séparés sauf `static/`)
* Safe area iOS gérée dans `base.html` — ne pas dupliquer
* Responsive mobile-first

---

# Workflow de développement

Pour implémenter une fonctionnalité :

1. Ajouter la logique métier dans le module `api/` approprié (ou créer un nouveau module)
2. Ajouter la route dans `api/index.py`
3. Créer ou modifier le template Jinja2
4. Tester en local
5. Mettre à jour `STATE.md` et `TASKS.md`
6. Commit + push sur la branche de travail

---

# Sécurité

Ne jamais committer :

* fichiers `.env`
* clés API
* credentials Supabase
* tokens

Toujours stocker les secrets dans les variables d'environnement.

---

# Priorités agent

Ordre de priorité lors de modifications :

1. Sécurité (pas de fuite de secrets, pas d'injection)
2. Intégrité des données (cohérence Supabase/SQLite)
3. Compatibilité mobile/PWA
4. Cohérence UI (base.html, safe area, responsive)
5. Performance

---

# Glossaire

**Séance** : session d'entraînement musculaire ou HIIT loggée.
**Inventaire / Programme** : liste des exercices et charges de référence de l'utilisateur.
**1RM** : One Rep Max — charge maximale estimée pour un exercice.
**Déload** : semaine de récupération à charge réduite, détectée automatiquement.
**Dirty** : entrée SQLite locale non encore synchronisée avec Supabase.
**Coach IA** : interface `intelligence.html` utilisant Claude pour analyser et suggérer.
