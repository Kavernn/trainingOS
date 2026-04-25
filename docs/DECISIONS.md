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

---

## 2026-04-25

**Décision** : Supersets encodés via 3 colonnes nullables sur `program_block_exercises` (`superset_group`, `superset_position`, `rest_after_superset`) plutôt qu'une table `supersets` dédiée.

**Raison** : Rétrocompatibilité totale — les exercices solo gardent ces colonnes à NULL sans impact sur les requêtes existantes. Une table séparée aurait requis des JOINs supplémentaires sur un chemin critique (fetch séance). La structure de superset est simple (paire A+B) et ne justifie pas une table dédiée.

---

**Décision** : Hints d'exercice exposés via le champ `tips TEXT` existant dans la table `exercises` (réutilisé) plutôt qu'une nouvelle colonne `hint`.

**Raison** : `tips` était déjà présent dans le schema comme "coaching cue" — même sémantique. Zéro migration nécessaire. Renommé conceptuellement en "hint" côté API/iOS uniquement (`inventory_hints` dans la réponse).

---

**Décision** : Repos uniform 120 s sur tous les supersets du programme UL/PPL (valeur utilisateur, vs 90/75/60 s du PDF d'origine).

**Raison** : Simplicité cognitive en séance — un seul chiffre à retenir. La colonne `rest_after_superset` reste flexible pour ajuster par exercice si besoin dans un programme futur.

---

**Décision** : Rendu superset dans `SeanceView` via un enum `ExerciseRenderItem` (`.superset` / `.solo`) calculé une fois en computed property, plutôt que détection inline dans le `ForEach`.

**Raison** : Évite le double-rendu de l'exercice B (qui apparaîtrait deux fois dans un ForEach naïf). La computed property construit la liste de render items en un seul passage (`Set<String> rendered`), garantissant un identifiant stable par item pour SwiftUI. Le fallback vers la liste plate quand `sessionSupersets` est vide préserve le comportement exact des anciennes sessions.
