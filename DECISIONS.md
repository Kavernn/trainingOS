# Décisions architecturales — TrainingOS

Les décisions importantes prises sur le projet sont consignées ici.
Les agents doivent ajouter une entrée lors de tout changement architectural majeur.

---

## 2026-03-07

**Décision** : Flask server-rendered (Jinja2) plutôt qu'un SPA React/Vue.

**Raison** : Stack minimaliste sans build step, déploiement simple sur Vercel en serverless Python, compatibilité native Capacitor via WKWebView.

---

**Décision** : Stockage clé/valeur JSON dans Supabase (table `kv`) plutôt qu'un schéma relationnel.

**Raison** : Flexibilité maximale pour faire évoluer les structures de données sans migrations, adéquat pour les volumes d'un utilisateur unique.

---

**Décision** : Couche offline-first avec SQLite local + Supabase (modes ONLINE / OFFLINE / HYBRID).

**Raison** : L'app doit fonctionner en salle sans connexion ; sync automatique au retour en ligne. Vercel étant read-only, SQLite n'est utilisé qu'en local/dev.

---

**Décision** : Capacitor 6 pour le packaging iOS plutôt qu'une app native Swift.

**Raison** : Réutilisation totale du code web existant (PWA), maintenance unique base de code, time-to-market réduit.

---

**Décision** : Anthropic Claude (Haiku/Sonnet) pour le coach IA, remplaçant OpenRouter/Mistral.

**Raison** : Meilleure qualité d'analyse fitness, API directe sans intermédiaire, SDK Python officiel (`anthropic`).

---

**Décision** : Remplacement de "Inventaire" par "Programme" dans l'UI.

**Raison** : Terminologie plus parlante pour l'utilisateur final ; la clé de stockage (`inventory`) reste inchangée pour la rétrocompatibilité des données.

---

**Décision** : Auto-update du Service Worker basé sur un hash de version Vercel.

**Raison** : Éviter les problèmes de cache PWA après déploiement sans action manuelle de l'utilisateur.
