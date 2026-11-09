# Safe production rollout — 2026-11-08

**STOP — canonical taxonomy validated, but production migration must wait for compatible client/backend release**

Arrêt avant déploiement et mutation, conformément à la section 6 de la demande. Le code iOS de référence reproduit une omission silencieuse de nouvelles cibles et des groupes non reconnus. Aucune preuve d’un build iOS compatible distribué/installé en production n’est disponible dans les éléments inspectés. Le commit distant est une référence de code, pas une preuve du binaire installé.

## Résultat

- Catalogue réel relu deux fois : **161 lignes, 142 actives, 19 archivées**, intégralement identiques à la fin de pass2.
- Migration de cette opération : **0/46**. Restent différés : **46/46**. Aucun déploiement backend/client.
- **13 ambiguïtés inchangées ; ambiguous exercises changed = 0.** Toutes les lignes archivées aussi inchangées.
- **182 tests backend et 35 tests iOS verts**, relancés pendant cette opération.
- Aucun nouveau changement de code de production : les correctifs compatibles validés en pass2 sont toujours locaux. Pas de changement de schéma.
- Les 64 fichiers dirty préexistants contrôlés par SHA-256 sont inchangés. Index vide ; aucun stage, commit, push, stash ou déploiement.

## COMPATIBILITY — défauts réellement identifiés

### Pas de rejet du décodeur

Un exécutable de contrôle a compilé les véritables `ExerciseMuscleMetadata` et `MuscleMapper` de la référence distante b23c8d2a1c1e1133353fdc4f0fa80a4d7e17f9a0. Les **46 métadonnées cibles se décodent sans erreur** : String et [String], aucun enum fermé pour ces champs. Les modèles ne justifient donc pas de prétendre que les 46 lignes feraient planter l’application.

### Dépendance de version iOS qui bloque le rollout

- **Six changements de groupe** introduisent Hanches/Autre, absents du mapping et de l’exclusion explicite de l’ancienne TrainingDoctrine. Ce chemin retourne nil et journalise `unknown muscle_group`. Cinq lignes étaient non canoniques ; Copenhagen Plank est le sixième changement Core → Hanches.
- **Trois nouvelles omissions démontrées, après comparaison avant/cible** : Rear delts Face Pull et Face Pull ajoutent Coiffe des rotateurs ; Hanging Leg Raise ajoute Fléchisseurs de hanche. L’ancien mapper n’a pas de zone pour ces cibles et les anciennes vues n’affichent pas de fallback textuel. Les autres cibles non représentées déjà présentes ne sont pas comptées abusivement comme des régressions du rollout.
- Les correctifs locaux exposent `unmappedMuscles` en texte, partagent le vocabulaire éditeur et traitent Hanches/Autre explicitement sans inventer de repères de volume. Il faut une version iOS contenant ces correctifs avant les mutations concernées.
- Trois lignes ajoutent des équipements (`dip_bars`, `medicine ball`) absents de la liste de choix de l’ancien éditeur : ce n’est pas un échec de décodage. L’éditeur compatible permet de les sélectionner et préserve les modalités non-force.

### Backend, stockage, serializers et anciennes valeurs

- Deux changements Brachialis → Brachial demandent une transition d’alias cohérente : l’ancien workload transforme Brachialis en Biceps, mais laisse Brachial brut. Le code local harmonise les alias sans réécrire les logs.
- Le backend local retourne une taxonomie détaillée cohérente via `normalize_metadata` / `detailed_target`. Le cockpit ne fusionne plus aveuglément les sous-régions avec un groupe et ne leur invente pas de MEV/MAV. Le volume et les patterns DNA normalisent les alias ; les anciens libellés restent tolérés.
- La migration 063 définit TEXT/TEXT[] et aucune contrainte anatomique fermée ; les checks tracking_type concernent un champ que ce rollout ne change pas. Aucun changement de schéma n’est prévu. Les CHECK réellement déployés n’ont pas été introspectés via SQL administrateur et aucune écriture de test n’a été faite.
- L’API de production `/api/inventory` répond **200 / 142 exercices** avec authentification existante. Les 46 lignes examinées sont présentes ; Brachialis, legs et Cardio sont encore bruts. Aucun appel save_exercise/classify utilisé pour « tester », car ces routes peuvent toucher les prescriptions.
- **31 lignes n’ont pas de rejet concret de schéma/décodage identifié.** Leur différé venait de la liste conservatrice pass2 : absence de repère != incapacité de stocker ou afficher une chaîne. Elles restent dans le lot gelé tant que l’ordre de livraison du lot complet n’est pas validé. Aucun nouveau vocabulaire proposé.

## DEFERRED 46 — carte des dépendances complète

Chaque ligne contient les valeurs réelles exportées avant toute mutation. dependencies-46.json/CSV fournit aussi le motif historique et les fichiers responsables. prepared-migration.json fige les 46 IDs autorisés, les préconditions exactes et les 13 exclusions, avec le statut BLOCKED_ON_CLIENT_RELEASE. Ce n’est pas une migration exécutée.

| ID | Exercice | Production actuelle | Cible validée | Cause / dépendance |
|---|---|---|---|---|
| 00332b97-110a-4915-b17a-4e2e49919e6d | Copenhagen Plank | {"muscle_group": "Core"} | {"muscle_group": "Hanches"} | client_doctrine: Hanches/Autre absent from legacy _dbToDoctrinal and _excludedFromVolume; warning unknown muscle_group + nil. Existing editor group, not a schema enum. |
| 0490140d-dfe8-4fe1-8463-90ffc2c93eab | Inverted Row | {"secondary_muscles": null} | {"secondary_muscles": ["Biceps", "Rhomboïdes"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| 10b42a6a-497c-42a9-a84a-45b2deacba3b | Romanian Deadlift | {"secondary_muscles": null} | {"secondary_muscles": ["Grand fessier", "Érecteurs du rachis"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| 148511ac-237c-432d-accb-1b5ebfe046a1 | Barbell Close-Grip Bench Press | {"secondary_muscles": null} | {"secondary_muscles": ["Pectoral majeur", "Deltoïde antérieur"]} | backend_stats_mapping: Legacy workload outputs ["Pectoral majeur", "Épaules"] for target ["Pectoral majeur", "Deltoïde antérieur"]. Shared detailed taxonomy required. |
| 2469a72a-0fed-4fe9-8287-0a48ea8cd033 | Lying Leg Curl | {"secondary_muscles": null} | {"secondary_muscles": ["Gastrocnémien"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| 290eb168-e05b-481f-9ef3-07051d6cbff0 | Hammer Curl | {"muscle_specific": "Brachialis"} | {"muscle_specific": "Brachial"} | backend_alias_transition: Legacy Brachialis resolves to Biceps in workload, Brachial is returned raw. Exact aliases need shared detailed normalization while both spellings coexist; decoder already accepts both. |
| 29153cb0-2fa5-4e66-bfc4-93b6c5914f23 | Lateral Bound | {"secondary_muscles": null} | {"secondary_muscles": ["Quadriceps", "Grand fessier"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| 2ae311da-6f2b-4683-b93a-81bd20b23e94 | Leg Curl | {"secondary_muscles": null} | {"secondary_muscles": ["Gastrocnémien"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| 3b4b4a2f-4bf3-4526-bbaa-e4af98c0884a | Back Squat | {"secondary_muscles": []} | {"secondary_muscles": ["Grand fessier"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| 3d10e32d-23a1-4168-8b9e-013beb210f57 | Box Jump | {"secondary_muscles": ["Fessiers", "Mollets"]} | {"secondary_muscles": ["Grand fessier", "Gastrocnémien"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| 413a9a12-4ed0-41d0-8497-3698ff40941b | Zone-2 (vélo/rameur) | {"muscle_group": "Cardio"} | {"muscle_group": "Autre"} | client_doctrine: Hanches/Autre absent from legacy _dbToDoctrinal and _excludedFromVolume; warning unknown muscle_group + nil. Existing editor group, not a schema enum. |
| 486b1277-3d39-4ac4-8247-b2b833ec03a8 | Dips | {"equipment": null} | {"equipment": ["dip_bars"]} | client_editor_options: String array decodes; dip_bars absent from legacy kEquipmentOptions. Local vocabulary adds existing seed options; no new load formula. |
| 5d26346d-6eb6-4d48-8790-7171a6d1e284 | Deep Barbell Squat | {"secondary_muscles": null} | {"secondary_muscles": ["Grand fessier"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| 5ea88c96-99b5-4a75-93a7-4d07ab68d9e9 | Seated Cable Row | {"secondary_muscles": null} | {"secondary_muscles": ["Biceps", "Rhomboïdes"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| 60017691-bc43-4eaa-86d8-c0844621b6ab | Cable Seated Row | {"secondary_muscles": null} | {"secondary_muscles": ["Biceps", "Rhomboïdes"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| 61ef73eb-53e4-464a-ae0f-bf2324d2fedb | Barbell Front Squat | {"secondary_muscles": null} | {"secondary_muscles": ["Grand fessier"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| 6db73454-2ed1-4ead-847c-a873e1588df9 | Intervalles (VO2) | {"muscle_group": "Cardio"} | {"muscle_group": "Autre"} | client_doctrine: Hanches/Autre absent from legacy _dbToDoctrinal and _excludedFromVolume; warning unknown muscle_group + nil. Existing editor group, not a schema enum. |
| 753adbf6-5828-4e48-8c4b-1afbf251866a | Deadlift | {"secondary_muscles": []} | {"secondary_muscles": ["Grand fessier", "Érecteurs du rachis"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| 781b2807-39ee-44e2-a783-084d41c8be1d | Dumbbell Hammer Curl | {"muscle_specific": "Brachialis"} | {"muscle_specific": "Brachial"} | backend_alias_transition: Legacy Brachialis resolves to Biceps in workload, Brachial is returned raw. Exact aliases need shared detailed normalization while both spellings coexist; decoder already accepts both. |
| 85313d3e-abab-484d-85e1-3a2700fdaed4 | Jump Squat | {"secondary_muscles": null} | {"secondary_muscles": ["Grand fessier", "Gastrocnémien"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| 8b81e6ed-06f7-41d2-a526-69e8de626e2e | Rear delts Face Pull | {"secondary_muscles": []} | {"secondary_muscles": ["Rhomboïdes", "Coiffe des rotateurs"]} | client_silent_omission: Legacy decoder succeeds, but newly added secondary targets have no zone and no text fallback: Coiffe des rotateurs |
| 935673ee-71f3-4a2d-8766-feae5969c9af | Medicine Ball Chest Pass | {"equipment": null} | {"equipment": ["medicine ball"]} | client_editor_options: String array decodes; medicine ball absent from legacy kEquipmentOptions. Local vocabulary adds existing seed options; no new load formula. |
| 93cc7342-2ded-4c95-bd91-0d47c46efe23 | Medicine Ball Slam | {"equipment": null} | {"equipment": ["medicine ball"]} | client_editor_options: String array decodes; medicine ball absent from legacy kEquipmentOptions. Local vocabulary adds existing seed options; no new load formula. |
| 941bd354-bb6a-421e-b86f-01d4176259c6 | Broad Jump | {"secondary_muscles": null} | {"secondary_muscles": ["Grand fessier", "Gastrocnémien"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| 9877faf0-f077-4de7-9d57-ddc851583396 | Rope Hammer Curl | {"secondary_muscles": ["Biceps brachial — courte portion", "Biceps brachial — longue portion", "Brachial"]} | {"secondary_muscles": ["Biceps", "Brachial"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| 98c0a477-4482-4184-bb99-bde8a77528f7 | Barbell Row | {"secondary_muscles": ["Rhomboïdes"]} | {"secondary_muscles": ["Biceps", "Rhomboïdes"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| 992c71f7-aec4-4265-9350-e5e76dcc01b0 | Bulgarian Split Squat | {"secondary_muscles": null} | {"secondary_muscles": ["Grand fessier"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| 9b496761-0cb5-4960-a82b-857968faef37 | Barbell Bent Over Row | {"secondary_muscles": null} | {"secondary_muscles": ["Biceps", "Rhomboïdes"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| b2457e20-6988-412e-9c80-21044a31b973 | Barbell Romanian Deadlift | {"secondary_muscles": []} | {"secondary_muscles": ["Grand fessier", "Érecteurs du rachis"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| b921a222-5892-4464-98a1-583bfa7d343a | Single Arm DB Overhead Press | {"secondary_muscles": null} | {"secondary_muscles": ["Triceps", "Deltoïde médial"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| bc9e81bf-119d-4c3f-a339-ae16c6d59526 | Hanging Leg Raise | {"secondary_muscles": null} | {"secondary_muscles": ["Fléchisseurs de hanche"]} | client_silent_omission: Legacy decoder succeeds, but newly added secondary targets have no zone and no text fallback: Fléchisseurs de hanche |
| bda0a383-f3fa-4d71-aae4-1be678dd4084 | Hack Squat | {"secondary_muscles": null} | {"secondary_muscles": ["Grand fessier"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| c8b5663e-cd99-4aec-a4f6-1cbc8df09868 | Meadows Row | {"secondary_muscles": []} | {"secondary_muscles": ["Biceps", "Rhomboïdes"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| c96cc070-d44c-44e4-9658-d40370ebf8e2 | Cossack Squat | {"secondary_muscles": ["Quadriceps", "Fessiers"], "muscle_group": "legs"} | {"secondary_muscles": ["Quadriceps", "Grand fessier"], "muscle_group": "Hanches"} | client_doctrine: Hanches/Autre absent from legacy _dbToDoctrinal and _excludedFromVolume; warning unknown muscle_group + nil. Existing editor group, not a schema enum. |
| cb6ba509-253a-44f7-ae93-3fc4578e2a55 | Single-Arm DB Row | {"secondary_muscles": null} | {"secondary_muscles": ["Biceps", "Rhomboïdes"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| cd09e6d0-9b9a-4ab0-9b1d-4c4a9ba2684b | Dumbbell Arnold Press | {"secondary_muscles": null} | {"secondary_muscles": ["Triceps", "Deltoïde médial"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| cdac5271-1a7a-4239-972a-fb6ebec1806c | 90/90 Hip + Band Shoulder Rotation | {"muscle_group": "Mobility"} | {"muscle_group": "Hanches"} | client_doctrine: Hanches/Autre absent from legacy _dbToDoctrinal and _excludedFromVolume; warning unknown muscle_group + nil. Existing editor group, not a schema enum. |
| cf4a7ad6-b59a-4fe9-80e3-72f62b94794f | Seated Leg Curl | {"secondary_muscles": null} | {"secondary_muscles": ["Gastrocnémien"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| cf7a77c8-9b70-4831-b436-06d360ccdff6 | Pendlay Row | {"secondary_muscles": []} | {"secondary_muscles": ["Biceps", "Rhomboïdes"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| d07b4c3a-07c1-46e4-a607-469f0f512e0e | Seated Z Press | {"secondary_muscles": null} | {"secondary_muscles": ["Triceps", "Deltoïde médial"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| ddc39015-32cd-43e9-891b-dc89f5c82e63 | Face Pull | {"secondary_muscles": []} | {"secondary_muscles": ["Rhomboïdes", "Coiffe des rotateurs"]} | client_silent_omission: Legacy decoder succeeds, but newly added secondary targets have no zone and no text fallback: Coiffe des rotateurs |
| e13acf43-f687-4a63-93e9-0b6ab7ca9400 | World's Greatest Stretch | {"muscle_group": "Mobility"} | {"muscle_group": "Hanches"} | client_doctrine: Hanches/Autre absent from legacy _dbToDoctrinal and _excludedFromVolume; warning unknown muscle_group + nil. Existing editor group, not a schema enum. |
| e5548034-a819-4579-8230-a933a7482e80 | Leg Press | {"secondary_muscles": null} | {"secondary_muscles": ["Grand fessier"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| eb20250a-5db1-4acf-8fc8-da5b7314f896 | Barbell Good Morning | {"secondary_muscles": null} | {"secondary_muscles": ["Grand fessier", "Érecteurs du rachis"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| f61760fc-5c55-44f9-a653-ac46f0f6a093 | Barbell Lunge | {"secondary_muscles": null} | {"secondary_muscles": ["Grand fessier"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |
| f7e5bdbf-3ce6-4ef2-b31b-966b516e1905 | Walking Lunges | {"secondary_muscles": null} | {"secondary_muscles": ["Grand fessier"]} | conservative_batch_ordering: No concrete decoder/schema rejection found. Pass2 used a conservative landmark allowlist; missing landmark is not inability to store/decode. Target strings already survive legacy serializer and mapper. Held with rollout because client release gate is not satisfied for the batch. |

## Cinq groupes non canoniques — mappings préparés, non appliqués

Il s’agit de cinq exercices portant trois anciennes valeurs distinctes, pas de cinq nouveaux groupes.

| ID | Exercice | Avant | Après validé | Pourquoi |
|---|---|---|---|---|
| 413a9a12-4ed0-41d0-8497-3698ff40941b | Zone-2 (vélo/rameur) | Cardio | Autre | Groupe Autre déjà présent dans l’éditeur, pour une modalité cardiovasculaire sans muscle squelettique principal. |
| 6db73454-2ed1-4ead-847c-a873e1588df9 | Intervalles (VO2) | Cardio | Autre | Groupe Autre déjà présent dans l’éditeur, pour une modalité cardiovasculaire sans muscle squelettique principal. |
| c96cc070-d44c-44e4-9658-d40370ebf8e2 | Cossack Squat | legs | Hanches | Groupe Hanches déjà présent dans l’éditeur, cible adducteurs ou région de mobilité conservée. |
| cdac5271-1a7a-4239-972a-fb6ebec1806c | 90/90 Hip + Band Shoulder Rotation | Mobility | Hanches | Groupe Hanches déjà présent dans l’éditeur, cible adducteurs ou région de mobilité conservée. |
| e13acf43-f687-4a63-93e9-0b6ab7ca9400 | World's Greatest Stretch | Mobility | Hanches | Groupe Hanches déjà présent dans l’éditeur, cible adducteurs ou région de mobilité conservée. |

Copenhagen Plank : 00332b97-110a-4915-b17a-4e2e49919e6d, Core → Hanches (adducteurs). Dépendance client identique, mais le groupe initial Core était déjà canonique.

## QUALITY GATE — données réelles de production

Contrôle de production-after.json, pas du candidat local. Actifs uniquement, hors les 13 ambiguïtés ; les archivées sont également auditées séparément dans production-quality.json.

| Contrôle | Nombre |
|---|---:|
| Principal manquant (force) | 0 |
| Groupes non canoniques | 5 |
| Muscles non canoniques | 2 |
| Primary/secondary overlap | 0 |
| Primary invalide / tableau | 0 |
| Secondary dupliqué | 0 |
| Patterns invalides | 0 |
| Types de charge invalides | 0 |
| Équipement non canonique | 0 |
| Équipement manquant | 3 |
| Groupe/cible incohérent | 2 |

Le gate production n’est **pas vert**. Les deux muscles non canoniques sont les deux Brachialis différés. Le principal est un scalaire ou le groupe fallback du contrat existant ; pas de nouveaux tableaux primary. Les ID/nom ne sont pas modifiés.

## AMBIGUITIES — explicitement exclues

- 1d8ed80c-702b-4d54-9d15-dd6eef47cb57 — Calf Raise
- 28614b32-1508-4cb2-8b38-f6b051127e48 — T-Bar Row
- 3546990d-0a44-46ba-a36b-7b551571c03b — Burpee
- 35ab117f-cd8e-4c71-b69b-f91f3676d818 — Dumbbell Pull Over
- 48b9b47f-2f16-4053-aec1-1f75e5e20992 — 6-Way Shoulder Raise
- 6ad2001a-43b9-4546-9681-7140c04dda77 — Medicine Ball Overhead Throw
- bd09ae7b-69df-4790-807e-b4f7b46baac4 — Chest press
- bdc9b9c7-a501-47d4-a414-ada214f5514b — Wide-Grip Cable Row
- c6b79878-6a18-4de2-a4d0-26b65ed069fe — Sandbag Bear Hug Squat
- f27c51f6-99a3-4aac-956a-90f385a5423e — Cable Crunch
- b95a3324-7813-4d73-b0de-6e20867b0983 — Overhead Press
- e0eeb2d6-092f-4b87-836a-fb24093ddcf8 — Weighted Crunch
- c9a0be3d-6761-4957-873d-a1b32f94ed8f — Goblet Squat

Comparaison intégrale avant/après : 13/13 identiques. Exclusions également inscrites dans prepared-migration.json.

## Ordre de reprise concret

1. Identifier/distribuer le build iOS contenant les corrections de Models/MuscleMapping, TrainingDoctrine, Inventaire et les fallback textuels. Fournir une preuve de version/build ou d’installation compatible ; la présence du code local, du simulateur ou de origin/master ne suffit pas.
2. Construire un artefact backend isolé à partir de la version de production vérifiée et des seuls fichiers listés dans files.json. Ne pas lancer un déploiement depuis ce working tree dirty. Les différences HEAD→origin/master inspectées ne touchent pas api/, mais la révision effectivement déployée reste à vérifier.
3. Déployer ce backend compatible ; vérifier l’API réelle et les deux formes legacy/canonique sans créer d’exercice ni appeler une route qui propage des prescriptions.
4. Re-fetch obligatoire des 46 lignes, vérifier les préconditions du manifeste et l’exclusion des ambiguïtés, puis mises à jour metadata-only par ID. Aucune modification de noms, types de calcul, bar_weight, logs, prescriptions ou relations.
5. Relecture exacte de chaque ligne, gate sur production réelle, puis smokes Catalogue/Stats/volume/Programme/recherche/filtres/progression. Aucune autorisation supplémentaire de migration de lignes archivées n’est inférée.

## VALIDATION / downstream smoke

- Tests locaux relancés : **182 Python / 35 iOS**, zéro échec. Logs : /tmp/trainingos-rollout-20261108/.
- Probe ancien client : 46/46 décodages, comparaisons des nouvelles omissions ; source précise dans legacy-client-probe.json.
- Build : build incrémental simulateur inclus dans les tests iOS réussi. Pas de modification Swift de production pendant cette opération ; build iPhone appareil de pass2 déjà validé, non relancé. Aucun clean, aucune suppression de DerivedData.
- Production : deux exports DB identiques et API Catalogue HTTP 200, 142 exercices. Premier appel sans authentification : 401 ; second avec la clé existante : 200. Aucun secret dans les rapports.
- Smokes **post-migration** Stats/volume/Programme/recherche-filtres/progression : non exécutés car aucune migration/déploiement n’a eu lieu. Les tests locaux correspondants passent ; ils ne sont pas présentés comme une preuve de production.
- git diff --check : réussi. 64 fichiers dirty préexistants identiques par hash ; index vide.

## FILES — périmètre exact du rollout préparé

### backend

- api/exercise_taxonomy.py
- api/exercise_taxonomy_data.py
- api/db_exercises.py
- api/analytics_adapter.py
- api/cockpit_analytics_service.py
- api/muscle_volume.py
- api/utils.py
- api/workout_dna.py
- api/routes/workout_exercises.py

### ios

- Models/MuscleMapping.swift
- Models/TrainingDoctrine.swift
- Views/Inventaire/InventaireView.swift
- Views/Dashboard/DashboardTodayCards.swift
- Views/Seance/SeanceView.swift
- Views/Seance/SessionSupportViews.swift

### scripts

- scripts/audit_exercise_catalogue.py
- scripts/audit_exercise_catalogue_legacy.py
- scripts/generate_catalogue_taxonomy_swift.py

### changed_or_new_tests

- tests/test_catalogue_taxonomy.py
- tests/test_exercise_catalogue_quality.py
- tests/test_analytics_adapter.py
- tests/test_cockpit_muscles_targets_and_effective_sets.py
- tests/test_inventory_exercise_routes.py
- TrainingOSTests/MuscleMapperTests.swift

### reports

- docs/audits/catalogue-2026-11-07/
- docs/audits/catalogue-2026-11-08-rollout/

### excluded_unrelated_dirty

- Services/SmartAlarmService.swift
- TrainingOS.xcodeproj/project.pbxproj
- TrainingOSTests/SmartAlarmServiceTests.swift
- TrainingOSTests/SmartAlarmPlatformTests.swift
- Views/Dashboard/DashboardRitualCards.swift
- Views/Settings/SmartAlarmSettingsView.swift
- Views/Programme/ProgrammeView.swift
- TrainingOSTests/StructureSessionChoiceTests.swift

Tous les changements de code listés existaient avant cette opération. Seul le dossier de rapport 2026-11-08-rollout est ajouté ici. Les rapports pass2 restent l’autorité ; hashes enregistrés dans authority.json.

## GIT

Master reste dirty et derrière origin/master de 9 commits au contrôle final. Aucun fichier stagé, aucun commit/push/stash. Aucun changement unrelated mélangé et aucun déploiement effectué. État complet : git-final.txt.

**STOP — canonical taxonomy validated, but production migration must wait for compatible client/backend release**
