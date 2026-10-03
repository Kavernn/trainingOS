# R11.0 — Progression Coaching

Implémentation locale, sans commit, push, déploiement ni mutation de compte réel.

## Ordre de mise en service

1. Appliquer `docs/migrations/096_progression_coaching.sql` dans le processus de migration habituel, avant de publier l'API. Cette passe ne l'a pas exécutée sur Supabase.
2. Le backend doit utiliser le rôle serveur `service_role` pour la RPC ; `anon` et `authenticated` n'ont pas le droit de l'appeler directement. L'authentification HTTP reste celle de l'API Flask.
3. Publier le backend puis utiliser le binaire iOS réparé. Les lectures classiques référencent les nouvelles colonnes : ne pas déployer le backend avant sa migration.
4. Effectuer le smoke ci-dessous avec de vraies recommandations. Aucun faux historique n'est nécessaire.

## Contrat

Le récapitulatif ferme sa propre sheet avant de demander le Coaching. L'owner local `ProgressionFlow` conserve date/type/nom et une génération ; Evening, Bonus et reprise n'appellent leur fermeture finale qu'après la décision Coaching. Le callback est consommé une seule fois. Une réponse périmée est rejetée. Le type Bonus est explicite.

Les suggestions de fin de séance sont relues sans cache stale : actionable, maintain-only, vide, HTTP, décodage, réseau, annulation et contexte obsolète sont distincts. Une erreur active permet Réessayer/Terminer ; une disparition normale ne déclenche pas d'alerte destructrice.

`POST /api/apply_progression` reçoit exercice, programme, contexte de séance, poids/schéma proposés et paire de référence attendue (nullable explicitement pour les données legacy). Les attentes proviennent de la lecture utilisée pour calculer les suggestions, pas d'une relecture ultérieure ni des poids du dernier log.

La RPC verrouille le contexte actif, la référence exercice et les prescriptions ciblées. Une transaction écrit charge/schéma/référence et le schéma du programme et de la séance concernés. Les autres programmes ne sont pas modifiés. Une prescription différente ou absente produit un conflit plutôt qu'une écriture silencieuse. Les conflits de référence produisent 409 ; un échec SQL annule tout. Une répétition après succès reçoit 409, pas une deuxième écriture. Aucun fallback vers les deux anciens setters.

Les séances classiques relisent les références explicitement appliquées après les suggestions automatiques. Les schémas approuvés sont identifiés par programme/séance et ne sont plus tronqués à trois séries dans le payload ; un override daté distinct reste prioritaire. L'ajustement de volume/fatigue existant n'est pas réécrit. L'historique effectué reste intact.

Le client ne confirme qu'un ACK `success:true`, décodable, avec paire après écriture correspondant à la demande. Une mise en file reste « En attente de synchronisation ». Les bytes et l'identité d'opération sont stables ; la queue existante bloque les doublons. Le replay valide aussi l'ACK avant invalidation. Timeout/perte de connexion ambiguë reste incertain et n'est pas rejoué automatiquement par l'infrastructure corrélée.

Chaque suggestion possède son état ; deux exercices sont indépendants et le même envoi est gardé avant suspension. Ignore utilise date/type/nom/exercice/type/valeurs/programme. Undo envoie les deux valeurs originales avec CAS sur les valeurs confirmées, y compris une ancienne charge NULL ; un échec reste visible. Les aperçus inline sans contexte de finalisation/CAS restent consultatifs, sans bouton de mutation trompeur.

## Limites explicites

- DAY COMPOSER COACHING : NOT YET INTEGRATED. Aucun fichier ou callback Day Composer modifié.
- Les anciens `workout_sessions` n'ont pas d'identifiant de programme. Les identités connues sont filtrées ; le fallback legacy demeure. On ne prétend pas isoler parfaitement les programmes pour des lignes qui n'en portent pas l'identité. Le même slot est prioritaire ; le déplacement AM/PM demande un overlap ; l'historique de plateau respecte le cutoff.
- La ligne déjà montée ne se transforme pas automatiquement de queued en confirmed au replay. L'ACK invalide les caches ; le prochain chargement réconcilie la lecture. Aucun polling ajouté.
- Le smoke visuel iPhone et le déploiement réel restent à faire. Une compilation sans signature n'installe pas l'app.
- Les tests PostgreSQL embarqués utilisent une connexion et un schéma minimal fidèle aux colonnes utilisées. Ils prouvent les écritures/rollback de la migration réelle, pas une course entre plusieurs connexions Supabase.

## Validation exécutée

- Baseline : 9 tests backend rouges (17 assertions/sous-cas en échec sur la route absente et le helper ancien). Les trois bugs backend obligatoires — route, partialité, stale — sont conservés et verts.
- Quatre contrats Swift communs appliqués au corps de code extrait de HEAD puis au contrôleur réparé : quatre FAIL → quatre PASS (lifecycle Evening, Bonus, erreur fetch, queued).
- `PYTHONDONTWRITEBYTECODE=1 .venv/bin/python tests/test_progression_coaching.py` : 31 tests PASS, dont matching, équipement, cutoff, validation, lecture de référence et schémas scoppés.
- `tests/progression_transaction.mjs` : 15 tests PASS sur la migration exacte dans PostgreSQL en mémoire, dont exceptions injectées aux deux écritures, rollback, CAS, Undo nullable, isolation du programme et privilèges RPC.
- XCTest hôte : 47 tests PASS (12 ProgressionCoaching, 8 ProgressionTransport, 21 OfflineCorrelation, 6 SyncManager). Modèle et queue sont les sources de production ; les méthodes API sont extraites sans modification, avec configuration, réseau et invalidation simulés. Aucun compte réel.
- Compilation incrémentale iOS Debug : PASS, `CODE_SIGNING_ALLOWED=NO`, sans clean ni full rebuild demandé.

Le runtime SQL est installé uniquement dans les artefacts, conformément au [mode PostgreSQL en mémoire de PGlite](https://pglite.dev/docs/). Pour rejouer le test, définir `PGLITE_MODULE` vers son `dist/index.js`, puis lancer `node tests/progression_transaction.mjs`. Il ne lit aucun secret ni configuration Supabase.

Artefacts et logs : `/Users/vincentpinard/.codex/measurements/progression-coaching-repair/`.

## Smoke après migration/backend corrigé

1. Morning : terminer une vraie séance, fermer le récap, vérifier Coaching et Appliquer confirmé ; vérifier la charge et le schéma à la prochaine lecture.
2. Evening : vérifier que Coaching reste affiché ; fermer/terminer Coaching, puis seulement constater la fermeture du parent.
3. Bonus : vérifier le type `bonus` et le même ordre de fermeture.
4. Erreur/offline : erreur fetch visible avec sortie sûre ; Apply queued sans « Appliqué » ; reconnecter puis recharger. Vérifier aussi qu'une ancienne recommandation en conflit n'écrase rien.
