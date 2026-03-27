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

---

## 2026-03-26

**Décision** : Migration de Capacitor/PWA vers une app **iOS native SwiftUI**.

**Raison** : Accès direct à HealthKit (background delivery, HRV, sommeil, FC), animations natives (haptics, confetti, Charts), performance supérieure en salle, APIs SwiftData pour offline queue.

---

**Décision** : RPE gradué à 5 niveaux dans `progression.py` (remplace thresholds binaires ≤6.0/≥8.5).

**Raison** : Les seuils binaires créaient des sauts brusques (ex: RPE 8.4 = maintien, RPE 8.5 = −full incrément). Le scale gradué permet des micro-ajustements (±demi-incrément) qui correspondent mieux à la réalité physiologique.

---

**Décision** : RIR (Reps In Reserve) capturé par set en parallèle du RPE par exercice.

**Raison** : Le RPE est déclaré après l'exercice entier (biais de confirmation). Le RIR par set capture l'effort en temps réel. Formule de fallback `rpe ≈ 10 − avg_rir` permet de l'utiliser dans l'algorithme de progression quand RPE absent.

---

**Décision** : `compute_progression_rate()` via régression linéaire sur 28 jours de 1RM (fenêtre glissante).

**Raison** : Un seul point de comparaison (session précédente) est trop sensible au bruit. La régression sur 4 semaines donne un signal de tendance robuste pour détecter un vrai stall vs fluctuation normale.

---

**Décision** : `detect_performance_drop()` déclenche une recommandation de déload indépendamment de la stagnation de poids.

**Raison** : Un athlète peut augmenter les charges mais voir son 1RM chuter (surmenage, mauvais sommeil). Détecter la chute 1RM ≥10% sur 3 sessions capture ce cas que la stagnation de poids manque.

---

**Décision** : Contexte coach IA en format terse (~1400 chars) plutôt que format verbose labelé (~3500 chars).

**Raison** : Claude comprend les abréviations numériques (LSS:72, ACWR:1.1, etc.) aussi bien que le format prose. Le format terse réduit les coûts token de ~50% par appel sans perte de qualité de réponse.

---

**Décision** : Narrative hebdomadaire cachée par clé `narrative_YYYY-WXX` (semaine ISO).

**Raison** : La narrative ne change pas significativement pendant la même semaine. Le cache par semaine évite des appels Claude répétés à chaque ouverture de l'IntelligenceView.
