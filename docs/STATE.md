# État du projet — TrainingOS

Dernière mise à jour : 2026-03-07

---

## Phase actuelle

Consolidation et polish — fonctionnalités core complètes, amélioration UX mobile en cours.

---

## Systèmes complétés

* Planificateur hebdomadaire (programme + jours de repos)
* Logging séances muscu + calcul 1RM + progression de charges
* Séances HIIT avec timer dédié (beeps, flash, options)
* Historique par date avec édition inline
* Statistiques (KPIs globaux, Personal Records, volume par groupe)
* Coach IA Claude (analyse programme, suggestions déload/HIIT)
* Tracker nutritionnel (calories, macros, déficit)
* Objectifs avec barre de progression
* Suivi poids corporel + tendance
* Composition corporelle (bodycomp)
* Système XP et progression
* Notes libres
* Profil utilisateur
* Couche offline-first (Supabase + SQLite + sync LWW)
* PWA (Service Worker auto-update, manifest, icônes)
* iOS natif via Capacitor 6 (safe area, splash, status bar)
* Responsive mobile complet sur toutes les pages

---

## En cours

* Consolidation et vérification des fichiers de documentation projet

---

## Prochaines étapes envisagées

1. Tests automatisés élargis (couverture isolation programme/historique déjà en place)
2. Synchronisation offline améliorée (UI indicateur dirty/sync)
3. Partage de programme entre utilisateurs
4. Notifications push (rappels séance)

---

## Dette technique connue

* `DEBUG` prints dans `db.py` — à remplacer par un vrai logger
* Pas de rate limiting sur les appels Claude (coût API non maîtrisé)
* Certains templates ont du CSS inline volumineux — candidats à externalisation
* Pas de tests pour les routes Flask (seulement logique métier isolation)
* `SECRET_KEY` avec valeur par défaut dans `index.py` — doit être forcé en prod

---

## Branches actives

| Branche | Objectif |
|---|---|
| `claude/mobile-training-os-access-CG3uq` | Branche de développement principale (agent) |
| `master` | Branche stable / production |
