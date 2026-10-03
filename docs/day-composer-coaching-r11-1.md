# R11.1 — Coaching Matin / Soir dans Day Composer

## Parcours

Le `DayComposerFinishCoordinator` admet une source au Coaching uniquement après reconciliation résolue et ACK métier final confirmé. Un transport pending, delivered-unverified, en conflit ou en échec n'est pas éligible. Le RPE explicite 6–10 et les écritures de finalisation restent inchangés.

Le récap par source reprend `DayComposerFinishStatus`. Un seul propriétaire de sheet séquence RPE → confirmation → récap → fermeture du récap → fetch → sheet R11.0. Le fetch ne démarre pas tant que le récap est affiché. Le parent Day Composer reste monté et les exercices de l'autre source restent accessibles.

`DayComposerCoachingCoordinator` est un adaptateur de navigation : il réutilise `ProgressionFlow`, `ProgressionContext` et `ProgressionSuggestionsSheet`. L'Apply, ses ACK, CAS, transaction, offline queue, Ignore, Undo et concurrence restent intégralement ceux de R11.0. Aucun backend ni SQL modifié.

## Identité et séquencement

Le contexte provient de l'identité capturée : date explicite, `morning`/`evening`, nom canonique `morningSession`/`eveningSession`. Il n'existe pas de Bonus ici. Programme, empreinte, date et noms sont vérifiés à l'admission ; validité du propriétaire, source et génération sont vérifiées après await.

La première source confirmée est présentée d'abord. À la restauration, `refreshSources()` sérialise les lectures Matin puis Soir et regroupe les demandes simultanées d’apparition/foreground. À la reprise d’un propriétaire suspendu, les deux sources unresolved sont ordonnées Matin puis Soir ; la priorité Soir reste conservée quand cette source vient d’être finalisée dans le parcours actif. Une source ne peut avoir qu'un fetch actif. Une génération locale rejette aussi les réponses de transports ignorant l’annulation, avant tout effet sur le propriétaire courant. Un ancien callback de fermeture ne peut pas résoudre la source suivante.

Actionable ouvre la sheet partagée, titrée « Coaching · Matin/Soir ». None et maintain-only résolvent sans sheet obligatoire. Une erreur affiche Réessayer / Continuer sans Coaching, sans annuler la completion de la source. Une annulation normale revient au récap sans fausse alerte.

« Journée terminée » nécessite les deux finalisations résolues ET toutes les décisions Coaching requises résolues. La fermeture explicite de la sheet est une décision, y compris avec une ligne queued. Aucun replay n'est attendu pour débloquer la navigation ; queued n'est jamais présenté comme confirmed.

## Reprise et prescriptions

Le seul nouvel état durable est un booléen UserDefaults de décision résolue, préfixe `dc-coaching-resolved-v1-`, limité à date + source + nom canonique. Aucun payload Apply ou fait de finalisation n'y est stocké. Il reste local à l'installation, sans expiration automatique ni suppression d'historique. Une autre date/source/séance possède une autre clé. Le programme est contrôlé à l’admission et après le fetch, mais n’entre pas dans ce marqueur de navigation. Les anciens marqueurs de la passe de développement incluant le programme ne sont ni effacés ni migrés ; ils peuvent conduire à représenter le récap et relire le Coaching, sans resend workout. Sa perte ne provoque qu'une nouvelle lecture du Coaching ; jamais une nouvelle finalisation automatique.

Sans marqueur, les preuves durables de finalisation existantes réadmettent la source, représentent son récap et relisent le Coaching. Cela couvre la fermeture avant fetch, pendant une suggestion non décidée et après un Apply queued dont la sheet n'avait pas encore été fermée. Après décision, la restauration ne représente pas ce Coaching. Ignore et le journal corrélé R11.0 gardent leurs propres protections.

Sur le propriétaire courant, une completion métier déjà résolue reste terminée lors d'un foreground hors ligne. Une nouvelle instance doit toujours reconstruire et vérifier les preuves existantes ; aucune observation distante isolée ne vaut ACK.

Lors du contrôle de fraîcheur de l'autre source, une prescription mise à jour après completion ne change pas rétroactivement l'identité de la source effectuée. Le lecteur compare le snapshot courant à l'original en conservant uniquement les schémas des sources déjà confirmées par ce propriétaire ET encore observées terminées. Date, programme, noms, IDs, ordre, groupes, repos, tracking et prescriptions des sources non terminées restent contrôlés. Aucun payload de finalisation n'est réécrit.

Limite conservée : une restauration avec un contexte de programme/plan devenu incompatible reste soumise aux gardes de provenance existantes. R11.1 ne migre pas un ancien journal vers une nouvelle identité de programme. Une ligne Apply déjà montée peut rester queued jusqu'à la prochaine relecture, comme en R11.0.

## Validation et smoke

Les tests ciblés couvrent Matin/Soir, double actionable, none/maintain, erreurs/retry/continuer, queued finalization interdit, single-flight, réponse stale, restauration, états Apply R11.0, double tap, Undo, completed-day et garde de prescription. Les régressions ProductFlow, finalization et mobilité sont exécutées séparément des suites générales.

Smoke utilisateur sur de vraies données uniquement :

1. Finaliser Matin avec son RPE, fermer le récap, vérifier Coaching si actionable.
2. Décider, puis poursuivre Soir sans fermeture du Day Composer.
3. Finaliser Soir ; vérifier que la journée attend la décision Coaching éventuelle.
4. Si une suggestion naturelle le permet, vérifier Apply hors ligne queued, puis reconnexion/relecture ; jamais confirmed avant ACK.

### Résultats de cette passe

- Trois tests de reproduction rouges avant intégration : Morning confirmé sans owner Coaching, Evening confirmé sans owner, journée terminée avant décision.
- 29 tests `DayComposerProgressionCoachingTests` PASS sur simulateur, dont rejet d'une réponse appartenant à un autre programme et maintien de la completion lors d'un foreground hors ligne.
- Régressions : 5 `DayComposerProductFlowTests`, 16 `DayComposerFinishCoordinatorTests`, 9 `DayComposerMobilityTests` PASS.
- Reprise sur `39c80c9` : trois nouveaux tests rouges puis verts (réponse obsolète, marqueur minimal, ordre de reprise), plus un test de restauration concurrente sans POST. Total : 71 tests ciblés PASS, incluant les 12 `ProgressionCoachingTests` R11.0 (Morning/Evening/Bonus, Apply, Ignore, Undo).
- Compilation incrémentale iPhone PASS et app installée après la reprise. Smoke R11.1 manuel à effectuer.
- Aucun pytest, changement backend ou déploiement. Le hotfix `AnyView(content)` et le test crash hors scope restent inchangés.
- La première tentative XCTest sur iPhone était bloquée par la signature du bundle de tests ; validation obtenue sur le cache simulateur existant, sans clean. Le smoke réel reste à effectuer par l'utilisateur.
