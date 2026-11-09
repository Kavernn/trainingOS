# Audit complet du catalogue — 2026-11-07

**STOP — catalogue taxonomy requires product decision before final normalization**

## CATALOGUE SUMMARY

Lecture de la table Supabase `exercises` : 161 lignes, dont 142 actives et 19 supprimées logiquement. Les 19 archivées sont inventoriées mais jamais modifiées. Aucun historique de séance consulté ni écrit.

| Mesure | Nombre |
|---|---:|
| total | 161 |
| active | 142 |
| archived | 19 |
| complete_before | 1 |
| missing_before | 119 |
| inconsistent_before | 7 |
| invalid_taxonomy_before | 131 |
| anatomically_suspicious_before | 6 |
| corrected | 94 |
| fields_corrected | 108 |
| ambiguous | 15 |
| unknown_group_after | 13 |
| findings_before | 523 |
| findings_after | 440 |

Les catégories sont cumulatives. « Complete » signifie compatible avec tous les contrôles du contrat actuel, pas seulement utilisable dans une séance. Les incompatibilités de vocabulaire expliquent le faible nombre de lignes complètes. Le catalogue n’est PAS entièrement validé/peuplé.

## Contrat découvert et décisions bloquantes

- Source effective : `api/db_exercises.py:get_exercises`, lignes actives, API dictionnaire par nom. `data/exercises.json` et `data/inventory.json` sont historiques, pas un catalogue exhaustif. Aucun nouvel identifiant créé.
- Principal : `muscle_specific` scalaire, fallback `muscle_group`; secondaires : `secondary_muscles` tableau (UI maximum 3); `muscles` tableau hérité. Aucun modèle multi-primary : un tableau dans muscle_specific est invalide. Aucun nouveau schéma.
- DB migration 063 : champs texte/tableaux sans CHECK anatomique. Migration 094 : 8 tracking types fermés (reps, time, carry, plyo, cardio, interval, protocol, mobility). La règle historique 067 endurance↔time ne décrit plus les seeds cardio/interval : ne pas la réappliquer.
- Éditeur Inventaire : 13 groupes, 17 patterns, 10 types de charge. Doctrine : 11 groupes de volume, alias et Cou explicitement exclu. MuscleMapper : 11 zones de silhouette. Backend utils : landmarks distincts et alias incomplets. Il n’existe PAS une taxonomie canonique unique cohérente entre ces couches.
- **Décision 1 — granularité :** permettre les muscles génériques (Quadriceps, Biceps brachial, Obliques, Gastrocnémien) dans l’éditeur, ou imposer une portion anatomique ? Recommandation : conserver les muscles génériques comme choix valides ; un nom de squat ne permet pas de sélectionner arbitrairement un vaste.
- **Décision 2 — groupes hors doctrine :** adducteurs/Hanches, tibial antérieur, avant-bras, cou et non-force : groupe de volume propre, fusion explicite ou exclusion ? L’éditeur classe tibial antérieur sous Mollets, la silhouette n’a pas de zone dédiée. Le protocole plancher pelvien est volontairement classé Cardio par le seed. Ne pas convertir silencieusement ces cas en force.
- **Décision 3 — patterns :** préférer les 17 clés snake_case de l’éditeur/DNA, mais définir le rattachement de Plyometric, Hip Abduction, Elbow Flexion/Extension et des complexes de mobilité avant migration exhaustive. Les alias simples ne résolvent pas ces choix.
- Type de charge conservé : barbell, dumbbell, cable_single, cable_double, press, fixed_weight, bodyweight, endurance, machine, landmine. `strength`, `hypertrophy`, `mobility` observés dans weight_type sont des catégories, pas des conventions de charge valides. Ne pas choisir une formule sans confirmer l’appareil.
- `load_profile`, `increment`, `bar_weight`, tracking, default_scheme, rest_seconds, noms/IDs et toutes les prescriptions sont inchangés. Equipment complété uniquement pour l’appareil principal déjà déclaré ; accessoires non inventés.

## Compatibilité downstream

| Consommateur | Contrat / constat |
|---|---|
| Stats silhouette — Models/MuscleMapping.swift | Principal spécifique puis groupe, secondaires uniques, fallback legacy ; pas de zones cou/avant-bras/adducteurs. |
| Doctrine — Models/TrainingDoctrine.swift:134 | Origine exacte de `unknown muscle_group` : ni _dbToDoctrinal ni _excludedFromVolume. Cou seul explicitement exclu. |
| Volume — api/muscle_volume.py | Clé spécifique prioritaire, sinon groupe ; renommage brut peut séparer les buckets. |
| Workload — api/analytics_adapter.py / utils.py | Canonicalisation via landmarks ; valeur inconnue conservée brute. Nouveaux synonymes locaux testés mais pas supposés déployés. |
| DNA — api/workout_dna.py | Compte les patterns bruts ; ratios lisent hinge/squat/push_horizontal/push_vertical uniquement. Hip Hinge et Horizontal Push actuels ne contribuent pas aux ratios correspondants. |
| Déséquilibre — api/muscle_imbalance_engine.py | Groupes français exacts en minuscules ; fusion Biceps+Avant-bras vers Biceps dans Doctrine non partagée ici. |
| Programme — api/routes/data_views.py | Transmet métadonnées de catalogue, sans mutation de programme ; noms/IDs conservés. |
| ExerciseCard / ExerciseViewModel | is_unilateral pilote les côtés des prochaines saisies ; 8 variantes explicites corrigées. Aucun log historique réécrit. |
| Inventaire filtres/recherche | Type/category exacts ; recherche nom/alternate_name. Aucun nom/alias de recherche changé. Strength/cardio et catégories vides restent mal représentés par filtres existants. |
| Progression — api/plateau.py, inventory.py | Groupes inférieurs exacts, type/bar_weight pour charge. Aucun calcul ni profil de charge changé ; Meadows Row reste landmine/landmine/45. |

## NORMALIZATION

- Appliqué : groupe Abdominaux → Core (mapping existant partagé) ; equipment câble/cable → Câble, poids du corps → Poids du corps, band → Bandes lorsque présent dans une ligne non ambiguë.
- Préparé mais **non appliqué en état final DB** : Droit abdominal → Droit de l’abdomen, Brachialis → Brachial, Trapèze supérieur/moyen/inférieur → Trapèze — chef correspondant. 13 champs remis à leur valeur initiale après contrôle de compatibilité production. Les 5 alias ajoutés dans api/utils.py doivent être déployés/vérifiés avant reprise ; aucun déploiement effectué.
- `pending-normalization.json` contient chaque ID et proposition. Aucun synonyme musculaire nouveau requis par la DB finale.

## MISSING DATA — avant correction

| Exercice | ID | Champs manquants |
|---|---|---|
| Inverted Row | 0490140d-dfe8-4fe1-8463-90ffc2c93eab | equipment, secondary_muscles |
| Romanian Deadlift | 10b42a6a-497c-42a9-a84a-45b2deacba3b | equipment, secondary_muscles |
| Chest-Supported DB Row | 11b465db-21c9-418e-ae02-67a00e447a85 | equipment |
| Barbell Close-Grip Bench Press | 148511ac-237c-432d-accb-1b5ebfe046a1 | equipment, secondary_muscles |
| Single-Arm Triceps Extension | 1519b8a5-c80a-44a9-83e1-d23a4a90437e | equipment |
| Leg Extension | 1639cf6d-8235-4e99-8bee-35d33b9911dc | equipment, secondary_muscles |
| Calf Raise | 1d8ed80c-702b-4d54-9d15-dd6eef47cb57 | equipment, secondary_muscles |
| Barbell Preacher Curl | 1f50f894-679d-427a-8ffc-fcd013dec943 | equipment, secondary_muscles |
| Unilateral lateral raises | 23c31a4a-84de-471d-9e0e-742920ae474a | equipment, secondary_muscles |
| Lying Leg Curl | 2469a72a-0fed-4fe9-8287-0a48ea8cd033 | equipment, secondary_muscles |
| T-Bar Row | 28614b32-1508-4cb2-8b38-f6b051127e48 | equipment |
| Hammer Curl | 290eb168-e05b-481f-9ef3-07051d6cbff0 | category, equipment |
| Lateral Bound | 29153cb0-2fa5-4e66-bfc4-93b6c5914f23 | category, equipment, load_profile, pattern, secondary_muscles, type |
| Hip Thrust | 29609082-555f-40eb-b3a8-bc01efe793f2 | equipment |
| Leg Curl | 2ae311da-6f2b-4683-b93a-81bd20b23e94 | equipment, secondary_muscles |
| Barbell Curl | 2e0827c6-05ad-486e-95b1-e40d0f4bc022 | equipment, secondary_muscles |
| Cable Curl | 2e69ba02-e925-4865-8cea-31cfaf108d10 | equipment, secondary_muscles |
| Cable Lateral Raise | 2f717ae8-72cb-4a3f-8324-a980f6b7ab6a | category, equipment |
| Burpee | 3546990d-0a44-46ba-a36b-7b551571c03b | equipment, secondary_muscles |
| Bayesian Biceps Curl | 38bebfbe-036e-4023-a4db-12863ace35ed | equipment, load_profile, secondary_muscles |
| Cable External Rotation | 3af0d483-cc9e-433c-9a21-3a86c549e77e | load_profile |
| Back Squat | 3b4b4a2f-4bf3-4526-bbaa-e4af98c0884a | equipment |
| EZ Bar Curl | 3b6c646a-133d-4618-9680-387786037816 | equipment, secondary_muscles |
| Abs wheel | 3d29d57a-7b3d-4e16-b87b-854651f94d68 | equipment, secondary_muscles |
| Incline DB Press | 3dd16c0e-5082-4950-a645-1db789171655 | category, equipment |
| Incline Cable Fly | 3eb47bc0-8e10-49f0-a4b8-2914db648503 | category, equipment, load_profile |
| Barbell Shrug | 3ff53dd3-caaf-4b29-bc97-21fbf66cdc84 | equipment, secondary_muscles |
| Dumbbell Decline Bench Press | 4024dde6-3c2c-4463-9935-9c74c7f63545 | equipment, secondary_muscles |
| Wrist Roller | 402e4fd4-1c97-413f-8f7b-5e2e1c4faf65 | equipment, load_profile, secondary_muscles |
| Barbell Jump Shrug | 45fb8027-6c8a-4104-9729-78e168056b30 | category, equipment, load_profile, pattern, secondary_muscles, type |
| Barbell Glute Bridge | 46dfd5a9-b52b-4690-ac22-b9064650f9eb | equipment, secondary_muscles |
| Dips | 486b1277-3d39-4ac4-8247-b2b833ec03a8 | equipment, secondary_muscles |
| 6-Way Shoulder Raise | 48b9b47f-2f16-4053-aec1-1f75e5e20992 | equipment, load_profile, secondary_muscles |
| Cable Pull-Through | 4f44fe97-2dd0-400f-a653-b6d91c3964b7 | equipment |
| Nordic Hamstring Curl | 517569ba-2fb9-4dd9-a5fa-b86ee6e0fabf | load_profile |
| Sissy Squat | 578c78d5-c413-4827-a3d9-ef044359049f | equipment, secondary_muscles |
| Deep Barbell Squat | 5d26346d-6eb6-4d48-8790-7171a6d1e284 | equipment, secondary_muscles |
| Seated Cable Row | 5ea88c96-99b5-4a75-93a7-4d07ab68d9e9 | equipment, secondary_muscles |
| Machine Rear Delt Flys | 5ed9acb6-76d6-408c-9aca-db573e1fb9dc | equipment, secondary_muscles |
| Lateral Raise | 5fe28d3e-6085-42c3-8973-d29f73766b55 | equipment, secondary_muscles |
| Cable Seated Row | 60017691-bc43-4eaa-86d8-c0844621b6ab | equipment, secondary_muscles |
| Barbell Front Squat | 61ef73eb-53e4-464a-ae0f-bf2324d2fedb | equipment, secondary_muscles |
| Lat Pulldown | 62f5d842-4cb6-4142-9287-5a9757ae3caf | equipment, secondary_muscles |
| Dumbbell Front Raise | 6722c8ed-08df-43ee-95c8-a02bb4fa57e3 | equipment, secondary_muscles |
| Abductor machine | 690a10d1-d233-4318-93dc-5d40b053a018 | category, equipment |
| Medicine Ball Overhead Throw | 6ad2001a-43b9-4546-9681-7140c04dda77 | category, equipment, load_profile, pattern, secondary_muscles, type |
| Incline DB Curl | 6b30f586-d5e6-4a41-9f28-56b9296dbea3 | equipment, secondary_muscles |
| Rear Delt Cable Fly | 71eefa04-2eba-472e-981c-fc3a3ff01eb8 | equipment, secondary_muscles |
| Dumbbell Fly | 733f7dc8-fc2b-412d-bad2-e4d3b4c2b6fa | equipment, secondary_muscles |
| Seated Calf Raise | 7381bd5d-dac0-4770-8873-4602ed8ed07e | equipment, secondary_muscles |
| Deadlift | 753adbf6-5828-4e48-8c4b-1afbf251866a | equipment |
| Skull Crusher (EZ) | 75c741f8-8ed6-4eb1-bf08-a45419908038 | load_profile |
| Dumbbell Hammer Curl | 781b2807-39ee-44e2-a783-084d41c8be1d | equipment, secondary_muscles |
| Bench Press | 78d5bcfc-2142-4dbd-a432-cf7921cf6c99 | equipment |
| Lateral Raises (un bras) | 78ed636f-c24a-4136-9d3b-f5317dff351f | equipment, secondary_muscles |
| Overhead Triceps Extension | 79bd63ce-e625-4e18-a7cd-aee68cc6f3fe | equipment, pattern, secondary_muscles |
| Single-Arm Lat Pulldown | 7d4bbd9f-60fd-4851-bd19-4dcfb00023f6 | equipment |
| Jump Squat | 85313d3e-abab-484d-85e1-3a2700fdaed4 | equipment, secondary_muscles |
| Spider Curl | 86bb5979-dd4b-47e4-9ec1-829f8125a76e | equipment, secondary_muscles |
| Dumbbell Biceps Curl | 8700b73b-11eb-47fb-b270-5014c7893c45 | equipment, secondary_muscles |
| Rear Delt Fly | 8f7fd7f9-aa3b-4231-a33b-492315b7b699 | equipment, secondary_muscles |
| Cable Fly / Pec Dec | 908921e6-83fe-4baf-87f3-361a678c47db | equipment, secondary_muscles |
| Standing Calf Raise | 90ec748d-710f-4e0f-951f-ee87581e2219 | equipment, secondary_muscles |
| Medicine Ball Chest Pass | 935673ee-71f3-4a2d-8766-feae5969c9af | category, equipment, load_profile, pattern, secondary_muscles, type |
| Medicine Ball Slam | 93cc7342-2ded-4c95-bd91-0d47c46efe23 | category, equipment, load_profile, pattern, secondary_muscles, type |
| Broad Jump | 941bd354-bb6a-421e-b86f-01d4176259c6 | category, equipment, load_profile, pattern, secondary_muscles, type |
| Prone Y-T-W Raises | 9501a76d-211f-4a83-9918-7aa8583075a8 | load_profile |
| Rack Pull | 97acf66d-e86f-4a02-a262-b6ac19dd88be | category, equipment, load_profile |
| Rope Hammer Curl | 9877faf0-f077-4de7-9d57-ddc851583396 | load_profile |
| Barbell Row | 98c0a477-4482-4184-bb99-bde8a77528f7 | equipment |
| Push-Up | 98e56d15-a23f-4b74-bd6f-5bb1fc97a73f | equipment, load_profile, secondary_muscles |
| Bulgarian Split Squat | 992c71f7-aec4-4265-9350-e5e76dcc01b0 | equipment, secondary_muscles |
| Barbell Bent Over Row | 9b496761-0cb5-4960-a82b-857968faef37 | equipment, secondary_muscles |
| Barbell Sumo Deadlift | 9b9e0927-c2f8-4596-af3e-9e10e4d984be | equipment, secondary_muscles |
| Flat DB Press | 9c04bf68-bdeb-44cb-92ff-eff643fb02d3 | equipment, secondary_muscles |
| Chin-Up | 9f0b0ed9-b7b0-45fa-8225-6cbd03915c3f | equipment, secondary_muscles |
| DB Bench Press | a6bcf831-7615-4cdc-b675-c18f871db05e | equipment, secondary_muscles |
| Barbell Incline Bench Press | ab4b06c0-a64f-4653-8d1a-86085afbfd6e | equipment, secondary_muscles |
| Pause Bench Press | adf08e12-6859-4f16-afa2-fe6d54e59971 | equipment, secondary_muscles |
| Barbell Romanian Deadlift | b2457e20-6988-412e-9c80-21044a31b973 | equipment |
| Plank | b28c8331-7839-404d-817e-3c1b7b2d784c | equipment, pattern, secondary_muscles |
| Barbell Lying Triceps Extension Skull Crusher | b490e7c5-86b9-4ce6-82b6-3917f8fc9e71 | equipment, secondary_muscles |
| Cable Y Raise | b86e3362-8734-4bdc-a432-779b21906dd4 | equipment, load_profile, secondary_muscles |
| Single Arm DB Overhead Press | b921a222-5892-4464-98a1-583bfa7d343a | equipment, load_profile, secondary_muscles |
| Reverse curls | b953ce24-0fe9-4180-ba98-919e90f99597 | equipment, secondary_muscles |
| Overhead Press | b95a3324-7813-4d73-b0de-6e20867b0983 | equipment, secondary_muscles |
| Dumbbell Shrug | ba63c8aa-900e-4d7b-be75-81f6dad7895e | equipment, secondary_muscles |
| Tibialis Raises | bbbcbcb3-6693-4111-9528-06b8f0d725d9 | load_profile |
| Hanging Leg Raise | bc9e81bf-119d-4c3f-a339-ae16c6d59526 | equipment, secondary_muscles |
| Hack Squat | bda0a383-f3fa-4d71-aae4-1be678dd4084 | equipment, secondary_muscles |
| Wide-Grip Cable Row | bdc9b9c7-a501-47d4-a414-ada214f5514b | load_profile |
| Sandbag Bear Hug Squat | c6b79878-6a18-4de2-a4d0-26b65ed069fe | equipment, muscle_specific |
| Dumbbell Wrist Curl | c74f4ad6-0243-4293-ad71-8cbef34a75cf | equipment, secondary_muscles |
| Meadows Row | c8b5663e-cd99-4aec-a4f6-1cbc8df09868 | equipment |
| Cossack Squat | c96cc070-d44c-44e4-9658-d40370ebf8e2 | equipment, load_profile |
| Goblet Squat | c9a0be3d-6761-4957-873d-a1b32f94ed8f | equipment, secondary_muscles |
| Single-Arm DB Row | cb6ba509-253a-44f7-ae93-3fc4578e2a55 | equipment, secondary_muscles |
| Dumbbell Arnold Press | cd09e6d0-9b9a-4ab0-9b1d-4c4a9ba2684b | equipment, secondary_muscles |
| Barbell Upright Row | cdf7b96a-722a-4267-ba32-a4dd816a4607 | equipment |
| Seated Leg Curl | cf4a7ad6-b59a-4fe9-80e3-72f62b94794f | equipment, load_profile, secondary_muscles |
| Seated Z Press | d07b4c3a-07c1-46e4-a607-469f0f512e0e | equipment, secondary_muscles |
| Dumbbell Concentration Curl | d2544c9f-2565-46f1-b344-adcc96b96484 | equipment, secondary_muscles |
| Russian Twist | d3d248fd-46b4-4f3b-bf92-bf6c329858cb | equipment, load_profile, secondary_muscles |
| Weighted Dips | d48ad620-1794-414d-ac93-a86e49085413 | load_profile |
| Cable Pull Over | d9b1359f-d412-4f59-8644-f22ecf3d82cd | equipment, secondary_muscles |
| Face Pull | ddc39015-32cd-43e9-891b-dc89f5c82e63 | category, equipment |
| Dumbbell Lateral Raise | de2c9e87-0a00-4d54-bc23-a4805413bcd3 | equipment, secondary_muscles |
| Weighted Crunch | e0eeb2d6-092f-4b87-836a-fb24093ddcf8 | equipment, secondary_muscles |
| Barbell Decline Bench Press | e2f5fab1-1382-49cd-bd1e-7007610f6af9 | equipment, secondary_muscles |
| Leg Press | e5548034-a819-4579-8230-a933a7482e80 | equipment, secondary_muscles |
| Pull-Up | e559c4a9-f67f-433e-83dd-8b8b4c916eeb | equipment, secondary_muscles |
| Farmer's Carry | eae74946-256e-4f20-bd65-70274dc039c4 | equipment, secondary_muscles |
| Barbell Good Morning | eb20250a-5db1-4acf-8fc8-da5b7314f896 | equipment, secondary_muscles |
| Deadhang | f435bd2e-1d48-4543-8c14-1112689a766e | equipment |
| Barbell Lunge | f61760fc-5c55-44f9-a653-ac46f0f6a093 | equipment, secondary_muscles |
| Walking Lunges | f7e5bdbf-3ce6-4ef2-b31b-966b516e1905 | equipment, load_profile, secondary_muscles |
| Dumbbell Rear Delt Flys | f82f7b09-970c-4f6d-b638-e3c0478aaba0 | equipment, load_profile, secondary_muscles |
| Cable Crossover | fa5bd0b0-9217-4c48-9d4f-b131d1908b0b | category, equipment, load_profile, pattern, secondary_muscles, type |
| Triceps Pushdown | fc506d23-f991-490a-8e46-37dc38461943 | category, equipment |

Un tableau secondaire `null` est une absence d’information ; `[]` est un choix explicitement vide. Les champs anatomiques/équipements optionnels non-force ne sont pas rendus obligatoires. Les lacunes non résolues sont listées dans unresolved.json, sans remplissage fictif.

## POPULATED — modifications finales effectivement appliquées

### Hollow Body Crunch — 0372093b-e1ff-4706-9863-82c82491a43b

- Primary : "Droit abdominal" → "Droit abdominal"
- Secondary : ["Obliques", "Hip Flexors"] → ["Obliques", "Hip Flexors"]
- Groupe : "Core" → "Core"
- equipment : ["poids du corps"] → ["Poids du corps"]
- Raison : Alias équipement vers choix existants de l’éditeur ; accessoires conservés.

### Romanian Deadlift — 10b42a6a-497c-42a9-a84a-45b2deacba3b

- Primary : "Biceps fémoral" → "Biceps fémoral"
- Secondary : null → null
- Groupe : "Ischio-jambiers" → "Ischio-jambiers"
- equipment : null → ["Barre"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Chest-Supported DB Row — 11b465db-21c9-418e-ae02-67a00e447a85

- Primary : "Grand dorsal" → "Grand dorsal"
- Secondary : ["Rhomboïdes", "Deltoïde postérieur"] → ["Rhomboïdes", "Deltoïde postérieur"]
- Groupe : "Dos" → "Dos"
- equipment : null → ["Haltères"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Barbell Close-Grip Bench Press — 148511ac-237c-432d-accb-1b5ebfe046a1

- Primary : "Triceps brachial" → "Triceps brachial"
- Secondary : null → null
- Groupe : "Triceps" → "Triceps"
- equipment : null → ["Barre"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Leg Extension — 1639cf6d-8235-4e99-8bee-35d33b9911dc

- Primary : "Quadriceps" → "Quadriceps"
- Secondary : null → null
- Groupe : "Quadriceps" → "Quadriceps"
- equipment : null → ["Machine"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Barbell Preacher Curl — 1f50f894-679d-427a-8ffc-fcd013dec943

- Primary : "Biceps brachial" → "Biceps brachial"
- Secondary : null → null
- Groupe : "Biceps" → "Biceps"
- equipment : null → ["Barre"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Unilateral lateral raises — 23c31a4a-84de-471d-9e0e-742920ae474a

- Primary : "Deltoïde médial" → "Deltoïde médial"
- Secondary : null → null
- Groupe : "Épaules" → "Épaules"
- equipment : null → ["Câble"]
- is_unilateral : false → true
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés. Variante explicitement à un bras/une jambe ; contrat per-side existant, historique non réécrit.

### Lying Leg Curl — 2469a72a-0fed-4fe9-8287-0a48ea8cd033

- Primary : "Biceps fémoral" → "Biceps fémoral"
- Secondary : null → null
- Groupe : "Ischio-jambiers" → "Ischio-jambiers"
- equipment : null → ["Machine"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Hammer Curl — 290eb168-e05b-481f-9ef3-07051d6cbff0

- Primary : "Brachialis" → "Brachialis"
- Secondary : [] → []
- Groupe : "Biceps" → "Biceps"
- equipment : [] → ["Haltères"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Hip Thrust — 29609082-555f-40eb-b3a8-bc01efe793f2

- Primary : "Grand fessier" → "Grand fessier"
- Secondary : ["Ischio-jambiers"] → ["Ischio-jambiers"]
- Groupe : "Fessiers" → "Fessiers"
- equipment : null → ["Barre"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Barbell Curl — 2e0827c6-05ad-486e-95b1-e40d0f4bc022

- Primary : "Biceps brachial" → "Biceps brachial"
- Secondary : null → null
- Groupe : "Biceps" → "Biceps"
- equipment : null → ["Barre"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Cable Curl — 2e69ba02-e925-4865-8cea-31cfaf108d10

- Primary : "Biceps brachial" → "Biceps brachial"
- Secondary : null → null
- Groupe : "Biceps" → "Biceps"
- equipment : null → ["Câble"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Cable Lateral Raise — 2f717ae8-72cb-4a3f-8324-a980f6b7ab6a

- Primary : "Deltoïde médial" → "Deltoïde médial"
- Secondary : [] → []
- Groupe : "Épaules" → "Épaules"
- equipment : [] → ["Câble"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Pallof Press — 308b33e0-78b2-4a21-9810-e6559f0e3807

- Primary : "Obliques" → "Obliques"
- Secondary : ["Épaules"] → ["Épaules"]
- Groupe : "Core" → "Core"
- equipment : ["câble"] → ["Câble"]
- Raison : Alias équipement vers choix existants de l’éditeur ; accessoires conservés.

### Bayesian Biceps Curl — 38bebfbe-036e-4023-a4db-12863ace35ed

- Primary : "Biceps brachial" → "Biceps brachial"
- Secondary : null → null
- Groupe : "Biceps" → "Biceps"
- equipment : null → ["Câble"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Cable External Rotation — 3af0d483-cc9e-433c-9a21-3a86c549e77e

- Primary : "Coiffe des rotateurs" → "Coiffe des rotateurs"
- Secondary : ["Deltoïde postérieur"] → ["Deltoïde postérieur"]
- Groupe : "Épaules" → "Épaules"
- equipment : ["cable", "handle"] → ["Câble", "handle"]
- Raison : Alias équipement vers choix existants de l’éditeur ; accessoires conservés.

### Back Squat — 3b4b4a2f-4bf3-4526-bbaa-e4af98c0884a

- Primary : "Quadriceps" → "Quadriceps"
- Secondary : [] → []
- Groupe : "Quadriceps" → "Quadriceps"
- equipment : [] → ["Barre"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### EZ Bar Curl — 3b6c646a-133d-4618-9680-387786037816

- Primary : "Biceps brachial" → "Biceps brachial"
- Secondary : null → null
- Groupe : "Biceps" → "Biceps"
- equipment : null → ["Barre"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Abs wheel — 3d29d57a-7b3d-4e16-b87b-854651f94d68

- Primary : "Droit abdominal" → "Droit abdominal"
- Secondary : null → null
- Groupe : "Abdominaux" → "Core"
- Raison : Alias exact déjà fusionné par TrainingDoctrine et utils.

### Incline DB Press — 3dd16c0e-5082-4950-a645-1db789171655

- Primary : "Pectoral supérieur" → "Pectoral supérieur"
- Secondary : [] → []
- Groupe : "Pectoraux" → "Pectoraux"
- equipment : [] → ["Haltères"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Incline Cable Fly — 3eb47bc0-8e10-49f0-a4b8-2914db648503

- Primary : "Pectoral supérieur" → "Pectoral supérieur"
- Secondary : [] → []
- Groupe : "Pectoraux" → "Pectoraux"
- equipment : [] → ["Câble"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Barbell Shrug — 3ff53dd3-caaf-4b29-bc97-21fbf66cdc84

- Primary : "Trapèze supérieur" → "Trapèze supérieur"
- Secondary : null → null
- Groupe : "Trapèzes" → "Trapèzes"
- equipment : null → ["Barre"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Dumbbell Decline Bench Press — 4024dde6-3c2c-4463-9935-9c74c7f63545

- Primary : "Pectoral inférieur" → "Pectoral inférieur"
- Secondary : null → null
- Groupe : "Pectoraux" → "Pectoraux"
- equipment : null → ["Haltères"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Barbell Glute Bridge — 46dfd5a9-b52b-4690-ac22-b9064650f9eb

- Primary : "Grand fessier" → "Grand fessier"
- Secondary : null → null
- Groupe : "Fessiers" → "Fessiers"
- equipment : null → ["Barre"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Cable Pull-Through — 4f44fe97-2dd0-400f-a653-b6d91c3964b7

- Primary : "Grand fessier" → "Grand fessier"
- Secondary : ["Ischio-jambiers"] → ["Ischio-jambiers"]
- Groupe : "Fessiers" → "Fessiers"
- equipment : null → ["Câble"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Deep Barbell Squat — 5d26346d-6eb6-4d48-8790-7171a6d1e284

- Primary : "Quadriceps" → "Quadriceps"
- Secondary : null → null
- Groupe : "Quadriceps" → "Quadriceps"
- equipment : null → ["Barre"]
- pattern : "hinge" → "squat"
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés. Squat explicite, pas hinge ; movement_pattern Squat déjà présent.

### Seated Cable Row — 5ea88c96-99b5-4a75-93a7-4d07ab68d9e9

- Primary : "Grand dorsal" → "Grand dorsal"
- Secondary : null → null
- Groupe : "Dos" → "Dos"
- equipment : null → ["Câble"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Machine Rear Delt Flys — 5ed9acb6-76d6-408c-9aca-db573e1fb9dc

- Primary : "Deltoïde postérieur" → "Deltoïde postérieur"
- Secondary : null → null
- Groupe : "Épaules" → "Épaules"
- equipment : null → ["Machine"]
- pattern : "horizontal_push" → "horizontal_pull"
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés. Écarté postérieur, cohérent avec movement_pattern Horizontal Pull existant.

### Lateral Raise — 5fe28d3e-6085-42c3-8973-d29f73766b55

- Primary : "Deltoïde médial" → "Deltoïde médial"
- Secondary : null → null
- Groupe : "Épaules" → "Épaules"
- equipment : null → ["Haltères"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Cable Seated Row — 60017691-bc43-4eaa-86d8-c0844621b6ab

- Primary : "Grand dorsal" → "Grand dorsal"
- Secondary : null → null
- Groupe : "Dos" → "Dos"
- equipment : null → ["Machine"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Barbell Front Squat — 61ef73eb-53e4-464a-ae0f-bf2324d2fedb

- Primary : "Quadriceps" → "Quadriceps"
- Secondary : null → null
- Groupe : "Quadriceps" → "Quadriceps"
- equipment : null → ["Barre"]
- pattern : "hinge" → "squat"
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés. Squat explicite, pas hinge ; movement_pattern Squat déjà présent.

### Lat Pulldown — 62f5d842-4cb6-4142-9287-5a9757ae3caf

- Primary : "Grand dorsal" → "Grand dorsal"
- Secondary : null → null
- Groupe : "Dos" → "Dos"
- equipment : null → ["Câble"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Dumbbell Front Raise — 6722c8ed-08df-43ee-95c8-a02bb4fa57e3

- Primary : "Deltoïde antérieur" → "Deltoïde antérieur"
- Secondary : null → null
- Groupe : "Épaules" → "Épaules"
- equipment : null → ["Haltères"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Abductor machine — 690a10d1-d233-4318-93dc-5d40b053a018

- Primary : "Moyen fessier" → "Moyen fessier"
- Secondary : [] → []
- Groupe : "Fessiers" → "Fessiers"
- equipment : [] → ["Machine"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Incline DB Curl — 6b30f586-d5e6-4a41-9f28-56b9296dbea3

- Primary : "Biceps brachial" → "Biceps brachial"
- Secondary : null → null
- Groupe : "Biceps" → "Biceps"
- equipment : null → ["Haltères"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Rear Delt Cable Fly — 71eefa04-2eba-472e-981c-fc3a3ff01eb8

- Primary : "Deltoïde postérieur" → "Deltoïde postérieur"
- Secondary : null → null
- Groupe : "Épaules" → "Épaules"
- equipment : null → ["Câble"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Dumbbell Fly — 733f7dc8-fc2b-412d-bad2-e4d3b4c2b6fa

- Primary : "Pectoral moyen" → "Pectoral moyen"
- Secondary : null → null
- Groupe : "Pectoraux" → "Pectoraux"
- equipment : null → ["Haltères"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Seated Calf Raise — 7381bd5d-dac0-4770-8873-4602ed8ed07e

- Primary : "Soléaire" → "Soléaire"
- Secondary : null → null
- Groupe : "Mollets" → "Mollets"
- equipment : null → ["Machine"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Deadlift — 753adbf6-5828-4e48-8c4b-1afbf251866a

- Primary : "Biceps fémoral — longue portion" → "Biceps fémoral — longue portion"
- Secondary : [] → []
- Groupe : "Ischio-jambiers" → "Ischio-jambiers"
- equipment : [] → ["Barre"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Dumbbell Hammer Curl — 781b2807-39ee-44e2-a783-084d41c8be1d

- Primary : "Brachialis" → "Brachialis"
- Secondary : null → null
- Groupe : "Biceps" → "Biceps"
- equipment : null → ["Haltères"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Bench Press — 78d5bcfc-2142-4dbd-a432-cf7921cf6c99

- Primary : "Pectoral moyen" → "Pectoral moyen"
- Secondary : ["Deltoïde antérieur"] → ["Deltoïde antérieur"]
- Groupe : "Pectoraux" → "Pectoraux"
- equipment : null → ["Barre"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Lateral Raises (un bras) — 78ed636f-c24a-4136-9d3b-f5317dff351f

- Primary : "Deltoïde médial" → "Deltoïde médial"
- Secondary : null → null
- Groupe : "Épaules" → "Épaules"
- equipment : null → ["Câble"]
- is_unilateral : false → true
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés. Variante explicitement à un bras/une jambe ; contrat per-side existant, historique non réécrit.

### Overhead Triceps Extension — 79bd63ce-e625-4e18-a7cd-aee68cc6f3fe

- Primary : "Triceps brachial" → "Triceps brachial"
- Secondary : null → null
- Groupe : "Triceps" → "Triceps"
- equipment : null → ["Câble"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Single-Arm Lat Pulldown — 7d4bbd9f-60fd-4851-bd19-4dcfb00023f6

- Primary : "Grand dorsal" → "Grand dorsal"
- Secondary : [] → []
- Groupe : "Dos" → "Dos"
- equipment : [] → ["Câble"]
- is_unilateral : false → true
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés. Variante explicitement à un bras/une jambe ; contrat per-side existant, historique non réécrit.

### Spider Curl — 86bb5979-dd4b-47e4-9ec1-829f8125a76e

- Primary : "Biceps brachial" → "Biceps brachial"
- Secondary : null → null
- Groupe : "Biceps" → "Biceps"
- equipment : null → ["Barre"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Dumbbell Biceps Curl — 8700b73b-11eb-47fb-b270-5014c7893c45

- Primary : "Biceps brachial" → "Biceps brachial"
- Secondary : null → null
- Groupe : "Biceps" → "Biceps"
- equipment : null → ["Haltères"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Rear delts Face Pull — 8b81e6ed-06f7-41d2-a526-69e8de626e2e

- Primary : "Deltoïde antérieur" → "Deltoïde postérieur"
- Secondary : [] → []
- Groupe : "Épaules" → "Épaules"
- Raison : Nom explicitement rear delts ; cohérent avec Face Pull existant, pas deltoïde antérieur.

### Rear Delt Fly — 8f7fd7f9-aa3b-4231-a33b-492315b7b699

- Primary : "Deltoïde postérieur" → "Deltoïde postérieur"
- Secondary : null → null
- Groupe : "Épaules" → "Épaules"
- equipment : null → ["Haltères"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Standing Calf Raise — 90ec748d-710f-4e0f-951f-ee87581e2219

- Primary : "Gastrocnémien" → "Gastrocnémien"
- Secondary : null → null
- Groupe : "Mollets" → "Mollets"
- equipment : null → ["Machine"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Rack Pull — 97acf66d-e86f-4a02-a262-b6ac19dd88be

- Primary : "Érecteurs du rachis" → "Érecteurs du rachis"
- Secondary : [] → []
- Groupe : "Dos" → "Dos"
- equipment : [] → ["Barre"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Barbell Row — 98c0a477-4482-4184-bb99-bde8a77528f7

- Primary : "Grand dorsal" → "Grand dorsal"
- Secondary : ["Rhomboïdes"] → ["Rhomboïdes"]
- Groupe : "Dos" → "Dos"
- equipment : null → ["Barre"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Bulgarian Split Squat — 992c71f7-aec4-4265-9350-e5e76dcc01b0

- Primary : "Quadriceps" → "Quadriceps"
- Secondary : null → null
- Groupe : "Quadriceps" → "Quadriceps"
- equipment : null → ["Haltères"]
- is_unilateral : false → true
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés. Variante explicitement à un bras/une jambe ; contrat per-side existant, historique non réécrit.

### Barbell Bent Over Row — 9b496761-0cb5-4960-a82b-857968faef37

- Primary : "Grand dorsal" → "Grand dorsal"
- Secondary : null → null
- Groupe : "Dos" → "Dos"
- equipment : null → ["Barre"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Barbell Sumo Deadlift — 9b9e0927-c2f8-4596-af3e-9e10e4d984be

- Primary : "Grand fessier" → "Grand fessier"
- Secondary : null → null
- Groupe : "Fessiers" → "Fessiers"
- equipment : null → ["Barre"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Flat DB Press — 9c04bf68-bdeb-44cb-92ff-eff643fb02d3

- Primary : "Pectoral moyen" → "Pectoral moyen"
- Secondary : null → null
- Groupe : "Pectoraux" → "Pectoraux"
- equipment : null → ["Haltères"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Chin-Up — 9f0b0ed9-b7b0-45fa-8225-6cbd03915c3f

- Primary : "Grand dorsal" → "Grand dorsal"
- Secondary : null → null
- Groupe : "Dos" → "Dos"
- equipment : null → ["Machine"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### DB Bench Press — a6bcf831-7615-4cdc-b675-c18f871db05e

- Primary : "Pectoral moyen" → "Pectoral moyen"
- Secondary : null → null
- Groupe : "Pectoraux" → "Pectoraux"
- equipment : null → ["Haltères"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Barbell Incline Bench Press — ab4b06c0-a64f-4653-8d1a-86085afbfd6e

- Primary : "Pectoral supérieur" → "Pectoral supérieur"
- Secondary : null → null
- Groupe : "Pectoraux" → "Pectoraux"
- equipment : null → ["Barre"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Pause Bench Press — adf08e12-6859-4f16-afa2-fe6d54e59971

- Primary : "Pectoral moyen" → "Pectoral moyen"
- Secondary : null → null
- Groupe : "Pectoraux" → "Pectoraux"
- equipment : null → ["Barre"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Barbell Romanian Deadlift — b2457e20-6988-412e-9c80-21044a31b973

- Primary : "Biceps fémoral" → "Biceps fémoral"
- Secondary : [] → []
- Groupe : "Ischio-jambiers" → "Ischio-jambiers"
- equipment : [] → ["Barre"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Plank — b28c8331-7839-404d-817e-3c1b7b2d784c

- Primary : "Droit abdominal" → "Droit abdominal"
- Secondary : null → null
- Groupe : "Abdominaux" → "Core"
- Raison : Alias exact déjà fusionné par TrainingDoctrine et utils.

### Barbell Lying Triceps Extension Skull Crusher — b490e7c5-86b9-4ce6-82b6-3917f8fc9e71

- Primary : "Triceps brachial" → "Triceps brachial"
- Secondary : null → null
- Groupe : "Triceps" → "Triceps"
- equipment : null → ["Barre"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Cable Y Raise — b86e3362-8734-4bdc-a432-779b21906dd4

- Primary : "Trapèze inférieur" → "Trapèze inférieur"
- Secondary : null → null
- Groupe : "Trapèzes" → "Trapèzes"
- equipment : null → ["Câble"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Single Arm DB Overhead Press — b921a222-5892-4464-98a1-583bfa7d343a

- Primary : "Deltoïde antérieur" → "Deltoïde antérieur"
- Secondary : null → null
- Groupe : "Épaules" → "Épaules"
- equipment : null → ["Haltères"]
- is_unilateral : false → true
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés. Variante explicitement à un bras/une jambe ; contrat per-side existant, historique non réécrit.

### Reverse curls — b953ce24-0fe9-4180-ba98-919e90f99597

- Primary : "Brachioradialis" → "Brachioradialis"
- Secondary : null → null
- Groupe : "Avant-bras" → "Avant-bras"
- equipment : null → ["Barre"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Overhead Press — b95a3324-7813-4d73-b0de-6e20867b0983

- Primary : "Deltoïde antérieur" → "Deltoïde antérieur"
- Secondary : null → null
- Groupe : "Épaules" → "Épaules"
- equipment : null → ["Haltères"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Dumbbell Shrug — ba63c8aa-900e-4d7b-be75-81f6dad7895e

- Primary : "Trapèze supérieur" → "Trapèze supérieur"
- Secondary : null → null
- Groupe : "Trapèzes" → "Trapèzes"
- equipment : null → ["Haltères"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Hanging Leg Raise — bc9e81bf-119d-4c3f-a339-ae16c6d59526

- Primary : "Droit abdominal" → "Droit abdominal"
- Secondary : null → null
- Groupe : "Abdominaux" → "Core"
- Raison : Alias exact déjà fusionné par TrainingDoctrine et utils.

### Hack Squat — bda0a383-f3fa-4d71-aae4-1be678dd4084

- Primary : "Quadriceps" → "Quadriceps"
- Secondary : null → null
- Groupe : "Quadriceps" → "Quadriceps"
- equipment : null → ["Machine"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Dumbbell Wrist Curl — c74f4ad6-0243-4293-ad71-8cbef34a75cf

- Primary : "Fléchisseurs du poignet" → "Fléchisseurs du poignet"
- Secondary : null → null
- Groupe : "Avant-bras" → "Avant-bras"
- equipment : null → ["Haltères"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Cable Woodchopper — c7bbf0fa-3c18-4154-bc80-f6cf9337c136

- Primary : "Obliques" → "Obliques"
- Secondary : ["Abdominaux"] → ["Abdominaux"]
- Groupe : "Core" → "Core"
- equipment : ["cable"] → ["Câble"]
- Raison : Alias équipement vers choix existants de l’éditeur ; accessoires conservés.

### Meadows Row — c8b5663e-cd99-4aec-a4f6-1cbc8df09868

- Primary : "Grand dorsal" → "Grand dorsal"
- Secondary : [] → []
- Groupe : "Dos" → "Dos"
- is_unilateral : false → true
- movement_pattern : "pull_vertical" → "pull_horizontal"
- equipment : [] → ["Barre"]
- Raison : Variante explicitement à un bras/une jambe ; contrat per-side existant, historique non réécrit. Row horizontal, pas tirage vertical ; clé déjà utilisée par l’éditeur et autres rows. Landmine existante : équipement barre ; type, poids barre et calcul conservés.

### Goblet Squat — c9a0be3d-6761-4957-873d-a1b32f94ed8f

- Primary : "Quadriceps" → "Quadriceps"
- Secondary : null → null
- Groupe : "Quadriceps" → "Quadriceps"
- equipment : null → ["Haltères"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Single-Arm DB Row — cb6ba509-253a-44f7-ae93-3fc4578e2a55

- Primary : "Grand dorsal" → "Grand dorsal"
- Secondary : null → null
- Groupe : "Dos" → "Dos"
- equipment : null → ["Haltères"]
- is_unilateral : false → true
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés. Variante explicitement à un bras/une jambe ; contrat per-side existant, historique non réécrit.

### Dumbbell Arnold Press — cd09e6d0-9b9a-4ab0-9b1d-4c4a9ba2684b

- Primary : "Deltoïde antérieur" → "Deltoïde antérieur"
- Secondary : null → null
- Groupe : "Épaules" → "Épaules"
- equipment : null → ["Haltères"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### 90/90 Hip + Band Shoulder Rotation — cdac5271-1a7a-4239-972a-fb6ebec1806c

- Primary : "Hanches" → "Hanches"
- Secondary : ["Épaules"] → ["Épaules"]
- Groupe : "Mobility" → "Mobility"
- equipment : ["band"] → ["Bandes"]
- Raison : Alias équipement vers choix existants de l’éditeur ; accessoires conservés.

### Barbell Upright Row — cdf7b96a-722a-4267-ba32-a4dd816a4607

- Primary : "Deltoïde médial" → "Deltoïde médial"
- Secondary : [] → []
- Groupe : "Épaules" → "Épaules"
- equipment : [] → ["Barre"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Seated Leg Curl — cf4a7ad6-b59a-4fe9-80e3-72f62b94794f

- Primary : "Biceps fémoral" → "Biceps fémoral"
- Secondary : null → null
- Groupe : "Ischio-jambiers" → "Ischio-jambiers"
- equipment : null → ["Machine"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Pendlay Row — cf7a77c8-9b70-4831-b436-06d360ccdff6

- Primary : "Grand dorsal" → "Grand dorsal"
- Secondary : [] → []
- Groupe : "Dos" → "Dos"
- movement_pattern : "pull_vertical" → "pull_horizontal"
- Raison : Row horizontal, pas tirage vertical ; clé déjà utilisée par l’éditeur et autres rows.

### Seated Z Press — d07b4c3a-07c1-46e4-a607-469f0f512e0e

- Primary : "Deltoïde antérieur" → "Deltoïde antérieur"
- Secondary : null → null
- Groupe : "Épaules" → "Épaules"
- equipment : null → ["Barre"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Dumbbell Concentration Curl — d2544c9f-2565-46f1-b344-adcc96b96484

- Primary : "Biceps brachial" → "Biceps brachial"
- Secondary : null → null
- Groupe : "Biceps" → "Biceps"
- equipment : null → ["Haltères"]
- is_unilateral : false → true
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés. Variante explicitement à un bras/une jambe ; contrat per-side existant, historique non réécrit.

### Russian Twist — d3d248fd-46b4-4f3b-bf92-bf6c329858cb

- Primary : "Obliques" → "Obliques"
- Secondary : null → null
- Groupe : "Abdominaux" → "Core"
- Raison : Alias exact déjà fusionné par TrainingDoctrine et utils.

### Cable Pull Over — d9b1359f-d412-4f59-8644-f22ecf3d82cd

- Primary : "Grand dorsal" → "Grand dorsal"
- Secondary : null → null
- Groupe : "Dos" → "Dos"
- equipment : null → ["Câble"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Face Pull — ddc39015-32cd-43e9-891b-dc89f5c82e63

- Primary : "Deltoïde postérieur" → "Deltoïde postérieur"
- Secondary : [] → []
- Groupe : "Épaules" → "Épaules"
- equipment : [] → ["Câble"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Dumbbell Lateral Raise — de2c9e87-0a00-4d54-bc23-a4805413bcd3

- Primary : "Deltoïde médial" → "Deltoïde médial"
- Secondary : null → null
- Groupe : "Épaules" → "Épaules"
- equipment : null → ["Haltères"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Weighted Crunch — e0eeb2d6-092f-4b87-836a-fb24093ddcf8

- Primary : "Droit abdominal" → "Droit abdominal"
- Secondary : null → null
- Groupe : "Abdominaux" → "Core"
- equipment : null → ["Câble"]
- Raison : Alias exact déjà fusionné par TrainingDoctrine et utils. Équipement principal déjà explicite dans type ; accessoires non supposés.

### Barbell Decline Bench Press — e2f5fab1-1382-49cd-bd1e-7007610f6af9

- Primary : "Pectoral inférieur" → "Pectoral inférieur"
- Secondary : null → null
- Groupe : "Pectoraux" → "Pectoraux"
- equipment : null → ["Barre"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Leg Press — e5548034-a819-4579-8230-a933a7482e80

- Primary : "Quadriceps" → "Quadriceps"
- Secondary : null → null
- Groupe : "Quadriceps" → "Quadriceps"
- equipment : null → ["Machine"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Farmer's Carry — eae74946-256e-4f20-bd65-70274dc039c4

- Primary : "Fléchisseurs des doigts" → "Fléchisseurs des doigts"
- Secondary : null → null
- Groupe : "Avant-bras" → "Avant-bras"
- equipment : null → ["Haltères"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Barbell Good Morning — eb20250a-5db1-4acf-8fc8-da5b7314f896

- Primary : "Biceps fémoral" → "Biceps fémoral"
- Secondary : null → null
- Groupe : "Ischio-jambiers" → "Ischio-jambiers"
- equipment : null → ["Barre"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Barbell Lunge — f61760fc-5c55-44f9-a653-ac46f0f6a093

- Primary : "Quadriceps" → "Quadriceps"
- Secondary : null → null
- Groupe : "Quadriceps" → "Quadriceps"
- equipment : null → ["Barre"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Walking Lunges — f7e5bdbf-3ce6-4ef2-b31b-966b516e1905

- Primary : "Quadriceps" → "Quadriceps"
- Secondary : null → null
- Groupe : "Quadriceps" → "Quadriceps"
- equipment : null → ["Haltères"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

### Dumbbell Rear Delt Flys — f82f7b09-970c-4f6d-b638-e3c0478aaba0

- Primary : "Deltoïde postérieur" → "Deltoïde postérieur"
- Secondary : null → null
- Groupe : "Épaules" → "Épaules"
- equipment : null → ["Haltères"]
- pattern : "horizontal_push" → "horizontal_pull"
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés. Écarté postérieur, cohérent avec movement_pattern Horizontal Pull existant.

### Triceps Pushdown — fc506d23-f991-490a-8e46-37dc38461943

- Primary : "Triceps brachial" → "Triceps brachial"
- Secondary : [] → []
- Groupe : "Triceps" → "Triceps"
- equipment : [] → ["Câble"]
- Raison : Équipement principal déjà explicite dans type ; accessoires non supposés.

## AMBIGUOUS — NEEDS PRODUCT DECISION

### Single-Arm Triceps Extension — 1519b8a5-c80a-44a9-83e1-d23a4a90437e

- Interprétations : Extension au-dessus de la tête ; pushdown bras le long du corps.
- Décision nécessaire : Position du bras pour valider longue portion et pattern.
- Données actuelles : `{"id": "1519b8a5-c80a-44a9-83e1-d23a4a90437e", "name": "Single-Arm Triceps Extension", "type": "cable", "category": "pull", "pattern": "pull", "level": "intermediate", "default_scheme": "3x8-12", "load_profile": "compound_hypertrophy", "muscles": ["triceps"], "increment": 5.0, "bar_weight": 0.0, "tracking_type": "reps", "rest_seconds": 120, "tips": null, "muscle_group": "Triceps", "muscle_specific": "Triceps — longue portion", "secondary_muscles": [], "movement_pattern": "pull_vertical", "weight_type": "cable_single", "equipment": [], "alternate_name": null, "is_unilateral": false, "deleted_at": null}`

### Calf Raise — 1d8ed80c-702b-4d54-9d15-dd6eef47cb57

- Interprétations : Debout (gastrocnémien) ; assis (soléaire, image actuelle).
- Décision nécessaire : Confirmer position du genou et machine.
- Données actuelles : `{"id": "1d8ed80c-702b-4d54-9d15-dd6eef47cb57", "name": "Calf Raise", "type": "machine", "category": "legs", "pattern": "isolation", "level": "beginner", "default_scheme": "3x12-15", "load_profile": "isolation", "muscles": ["calves", "soleus"], "increment": 5.0, "bar_weight": 0.0, "tracking_type": "reps", "rest_seconds": 120, "tips": "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Seated_Calf_Raise/1.jpg", "muscle_group": "Mollets", "muscle_specific": "Gastrocnémien", "secondary_muscles": null, "movement_pattern": "Isolation", "weight_type": "machine", "equipment": null, "alternate_name": null, "is_unilateral": false, "deleted_at": null}`

### T-Bar Row — 28614b32-1508-4cb2-8b38-f6b051127e48

- Interprétations : Landmine libre ; machine T-bar avec support thoracique (image actuelle).
- Décision nécessaire : Confirmer appareil et convention de charge.
- Données actuelles : `{"id": "28614b32-1508-4cb2-8b38-f6b051127e48", "name": "T-Bar Row", "type": "barbell", "category": "pull", "pattern": "horizontal_pull", "level": "intermediate", "default_scheme": "4x8-10", "load_profile": "compound_hypertrophy", "muscles": ["lats", "rhomboids", "traps", "biceps"], "increment": 5.0, "bar_weight": 45.0, "tracking_type": "reps", "rest_seconds": 120, "tips": "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Lying_T-Bar_Row/1.jpg", "muscle_group": "Dos", "muscle_specific": "Grand dorsal", "secondary_muscles": ["Rhomboïdes"], "movement_pattern": "Horizontal Pull", "weight_type": "barbell", "equipment": null, "alternate_name": null, "is_unilateral": false, "deleted_at": null}`

### Leg Curl — 2ae311da-6f2b-4683-b93a-81bd20b23e94

- Interprétations : Leg curl assis ; couché ; debout unilatéral.
- Décision nécessaire : Position et machine (ne pas inventer une portion musculaire).
- Données actuelles : `{"id": "2ae311da-6f2b-4683-b93a-81bd20b23e94", "name": "Leg Curl", "type": "machine", "category": "legs", "pattern": "hinge", "level": "beginner", "default_scheme": "3x10-12", "load_profile": "isolation", "muscles": ["calves", "hamstrings"], "increment": 5.0, "bar_weight": 0.0, "tracking_type": "reps", "rest_seconds": 120, "tips": "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Seated_Leg_Curl/1.jpg", "muscle_group": "Ischio-jambiers", "muscle_specific": "Biceps fémoral", "secondary_muscles": null, "movement_pattern": "Isolation", "weight_type": "machine", "equipment": null, "alternate_name": null, "is_unilateral": false, "deleted_at": null}`

### Burpee — 3546990d-0a44-46ba-a36b-7b551571c03b

- Interprétations : Avec pompe ; sans pompe ; variante avec saut.
- Décision nécessaire : Séquence exacte avant attribution musculaire principale.
- Données actuelles : `{"id": "3546990d-0a44-46ba-a36b-7b551571c03b", "name": "Burpee", "type": "bodyweight", "category": "core", "pattern": "mobility", "level": "intermediate", "default_scheme": "3x8-12", "load_profile": "compound_hypertrophy", "muscles": ["cardiovascular system", "quadriceps", "hamstrings", "calves", "shoulders", "chest"], "increment": 5.0, "bar_weight": 0.0, "tracking_type": "reps", "rest_seconds": 120, "tips": "Start in a standing position with your feet shoulder-width apart.. Lower your body into a squat position by bending your knees and placing your hands on the floor in front of you.", "muscle_group": "Pectoraux", "muscle_specific": "Pectoral moyen", "secondary_muscles": null, "movement_pattern": "Gainage", "weight_type": "bodyweight", "equipment": null, "alternate_name": null, "is_unilateral": false, "deleted_at": null}`

### Dumbbell Pull Over — 35ab117f-cd8e-4c71-b69b-f91f3676d818

- Interprétations : Pull-over haltère (nom) ; machine (type et équipement).
- Décision nécessaire : Confirmer appareil réel, puis attribution pectoraux/dorsaux selon exécution.
- Données actuelles : `{"id": "35ab117f-cd8e-4c71-b69b-f91f3676d818", "name": "Dumbbell Pull Over", "type": "machine", "category": "push", "pattern": "push", "level": "intermediate", "default_scheme": "3x8-12", "load_profile": "compound_hypertrophy", "muscles": ["back"], "increment": 5.0, "bar_weight": 0.0, "tracking_type": "reps", "rest_seconds": 120, "tips": null, "muscle_group": "Dos", "muscle_specific": "Grand dorsal", "secondary_muscles": ["Grand rond", "Pectoral majeur — chef costal", "Triceps — longue portion"], "movement_pattern": "push_vertical", "weight_type": "machine", "equipment": ["Machine"], "alternate_name": null, "is_unilateral": false, "deleted_at": null}`

### 6-Way Shoulder Raise — 48b9b47f-2f16-4053-aec1-1f75e5e20992

- Interprétations : Séquence élévations latérales/frontales ; séquence incluant rotation externe.
- Décision nécessaire : Décrire les six phases et choisir attribution principale unique.
- Données actuelles : `{"id": "48b9b47f-2f16-4053-aec1-1f75e5e20992", "name": "6-Way Shoulder Raise", "type": "dumbbell", "category": "push", "pattern": "horizontal_push", "level": "intermediate", "default_scheme": "3x6-10", "load_profile": null, "muscles": ["rear delts", "rhomboids", "rotators", "shoulders", "traps"], "increment": 5.0, "bar_weight": 0.0, "tracking_type": "reps", "rest_seconds": null, "tips": null, "muscle_group": "Épaules", "muscle_specific": "Deltoïdes", "secondary_muscles": null, "movement_pattern": "Isolation", "weight_type": "dumbbell", "equipment": null, "alternate_name": null, "is_unilateral": false, "deleted_at": null}`

### Medicine Ball Overhead Throw — 6ad2001a-43b9-4546-9681-7140c04dda77

- Interprétations : Lancer vers l’avant au-dessus de la tête ; lancer arrière en triple extension.
- Décision nécessaire : Direction du lancer et modalité de charge.
- Données actuelles : `{"id": "6ad2001a-43b9-4546-9681-7140c04dda77", "name": "Medicine Ball Overhead Throw", "type": null, "category": null, "pattern": null, "level": null, "default_scheme": "4x5", "load_profile": null, "muscles": [], "increment": 5, "bar_weight": 0, "tracking_type": "plyo", "rest_seconds": null, "tips": null, "muscle_group": "Épaules", "muscle_specific": "Deltoïde antérieur", "secondary_muscles": null, "movement_pattern": "Plyometric", "weight_type": "endurance", "equipment": null, "alternate_name": null, "is_unilateral": false, "deleted_at": null}`

### Cable Fly / Pec Dec — 908921e6-83fe-4baf-87f3-361a678c47db

- Interprétations : Écarté à deux piles ; pec-deck à pile unique.
- Décision nécessaire : Confirmer si une seule variante ou une alternative produit.
- Données actuelles : `{"id": "908921e6-83fe-4baf-87f3-361a678c47db", "name": "Cable Fly / Pec Dec", "type": "cable_double", "category": "push", "pattern": "isolation", "level": "beginner", "default_scheme": "3x12-15", "load_profile": "isolation", "muscles": ["pectorals"], "increment": 2.5, "bar_weight": 0.0, "tracking_type": "reps", "rest_seconds": 120, "tips": "Câble croisé · stretch en bas · squeeze en haut", "muscle_group": "Pectoraux", "muscle_specific": "Pectoral moyen", "secondary_muscles": null, "movement_pattern": "Horizontal Push", "weight_type": "cable_double", "equipment": null, "alternate_name": null, "is_unilateral": false, "deleted_at": null}`

### Chest press — bd09ae7b-69df-4790-807e-b4f7b46baac4

- Interprétations : Presse horizontale ; presse inclinée (chef claviculaire actuel).
- Décision nécessaire : Angle et modèle de machine.
- Données actuelles : `{"id": "bd09ae7b-69df-4790-807e-b4f7b46baac4", "name": "Chest press", "type": "machine", "category": "push", "pattern": "push", "level": "beginner", "default_scheme": "3x8-12", "load_profile": "compound_hypertrophy", "muscles": ["chest"], "increment": 5.0, "bar_weight": 0.0, "tracking_type": "reps", "rest_seconds": null, "tips": null, "muscle_group": "Pectoraux", "muscle_specific": "Pectoral majeur — chef claviculaire", "secondary_muscles": ["Deltoïde antérieur", "Triceps — chef latéral", "Triceps — chef médial"], "movement_pattern": "push_horizontal", "weight_type": "machine", "equipment": ["Machine"], "alternate_name": null, "is_unilateral": false, "deleted_at": null}`

### Wide-Grip Cable Row — bdc9b9c7-a501-47d4-a414-ada214f5514b

- Interprétations : Poulie à pile unique ; machine à bras indépendants.
- Décision nécessaire : Confirmer convention machine/câble et trajectoire.
- Données actuelles : `{"id": "bdc9b9c7-a501-47d4-a414-ada214f5514b", "name": "Wide-Grip Cable Row", "type": "machine", "category": "pull", "pattern": "pull", "level": "", "default_scheme": "3x8-12", "load_profile": null, "muscles": ["back"], "increment": 5.0, "bar_weight": 0.0, "tracking_type": "reps", "rest_seconds": null, "tips": null, "muscle_group": "Dos", "muscle_specific": "Grand dorsal", "secondary_muscles": ["Rhomboïdes", "Trapèze — chef inférieur", "Trapèze — chef moyen"], "movement_pattern": "pull_horizontal", "weight_type": "machine", "equipment": ["Machine"], "alternate_name": null, "is_unilateral": false, "deleted_at": null}`

### Sandbag Bear Hug Squat — c6b79878-6a18-4de2-a4d0-26b65ed069fe

- Interprétations : Sandbag tenu contre soi ; machine press (type actuel).
- Décision nécessaire : Confirmer appareil et type de charge supporté pour sandbag.
- Données actuelles : `{"id": "c6b79878-6a18-4de2-a4d0-26b65ed069fe", "name": "Sandbag Bear Hug Squat", "type": "press", "category": "legs", "pattern": "squat", "level": "intermediate", "default_scheme": "3x6-10", "load_profile": "compound_heavy", "muscles": ["quads"], "increment": 5.0, "bar_weight": 0.0, "tracking_type": "reps", "rest_seconds": 120, "tips": null, "muscle_group": "Quadriceps", "muscle_specific": null, "secondary_muscles": ["Biceps fémoral — longue portion", "Grand adducteur", "Grand fessier"], "movement_pattern": "squat", "weight_type": "press", "equipment": [], "alternate_name": null, "is_unilateral": false, "deleted_at": null}`

### Cossack Squat — c96cc070-d44c-44e4-9658-d40370ebf8e2

- Interprétations : Mobilité latérale ; squat latéral de force au poids du corps.
- Décision nécessaire : Modalité et traitement des adducteurs dans le volume.
- Données actuelles : `{"id": "c96cc070-d44c-44e4-9658-d40370ebf8e2", "name": "Cossack Squat", "type": "bodyweight", "category": "legs", "pattern": "lunge", "level": "beginner", "default_scheme": "2x6", "load_profile": null, "muscles": ["adductors", "quads", "glutes"], "increment": 0, "bar_weight": 0, "tracking_type": "reps", "rest_seconds": 60, "tips": "Talons au sol, jambe tendue orteils au plafond, torse droit, descente profonde.", "muscle_group": "legs", "muscle_specific": "Adducteurs", "secondary_muscles": ["Quadriceps", "Fessiers"], "movement_pattern": "lunge", "weight_type": "mobility", "equipment": [], "alternate_name": null, "is_unilateral": true, "deleted_at": null}`

### Weighted Dips — d48ad620-1794-414d-ac93-a86e49085413

- Interprétations : Buste incliné orienté pectoraux ; buste vertical orienté triceps.
- Décision nécessaire : Technique et convention charge additionnelle/poids total.
- Données actuelles : `{"id": "d48ad620-1794-414d-ac93-a86e49085413", "name": "Weighted Dips", "type": "bodyweight", "category": "push", "pattern": "push_horizontal", "level": "intermediate", "default_scheme": "4x6-10", "load_profile": null, "muscles": ["lower_chest", "triceps", "front_delts"], "increment": 2.5, "bar_weight": 0, "tracking_type": "reps", "rest_seconds": 150, "tips": "Torse légèrement penché avant, épaules loin des oreilles, descente contrôlée.", "muscle_group": "Pectoraux", "muscle_specific": "Pectoral inférieur", "secondary_muscles": ["Triceps", "Deltoïde antérieur"], "movement_pattern": "push_horizontal", "weight_type": "strength", "equipment": ["dip_bars", "weight_belt"], "alternate_name": null, "is_unilateral": false, "deleted_at": null}`

### Cable Crunch — f27c51f6-99a3-4aac-956a-90f385a5423e

- Interprétations : Une pile ; deux piles (weight_type actuel, type cable).
- Décision nécessaire : Confirmer nombre de piles et convention de saisie.
- Données actuelles : `{"id": "f27c51f6-99a3-4aac-956a-90f385a5423e", "name": "Cable Crunch", "type": "cable", "category": "strength", "pattern": "core", "level": "beginner", "default_scheme": "3x12-15", "load_profile": "isolation", "muscles": ["core"], "increment": 2.5, "bar_weight": 0, "tracking_type": "reps", "rest_seconds": 60, "tips": "À genoux, fléchissez la colonne (pas les hanches). Contraction maximale au bas. Coudes fixes.", "muscle_group": "Core", "muscle_specific": "Droit abdominal", "secondary_muscles": ["Obliques"], "movement_pattern": "Gainage", "weight_type": "cable_double", "equipment": ["câble"], "alternate_name": "Crunch Poulie", "is_unilateral": false, "deleted_at": null}`

## ANATOMICALLY SUSPICIOUS

- Rear delts Face Pull : Deltoïde antérieur malgré rear delts explicite (corrigé).
- Copenhagen Plank : Adducteurs principaux mais groupe Core ; aucun groupe adducteurs dans doctrine.
- Wall Slides : Trapèze inférieur avec groupe Épaules ; posture/serratus non décrits.
- Nordic Hamstring Curl : Flexion du genou classée hinge ; fessiers secondaires à revoir.
- Sandbag Bear Hug Squat : Type press et principal spécifique absent pour un sandbag.
- Burpee : Pectoral principal et pattern mobilité/gainage malgré séquence non définie.

## unknown muscle_group restant

13 exercices ; valeurs : Cardio, Jambes, Mobility, arms, legs.

- Thoracic Extension + Open Book — 112bc757-0b40-480c-9815-95064c0a81a9 : Mobility
- Cat-Cow + Thoracic Rotation — 18ae9f4c-94b4-4dab-b4be-4f2b64a3fe85 : Mobility
- Box Jump — 3d10e32d-23a1-4168-8b9e-013beb210f57 : Jambes
- Zone-2 (vélo/rameur) — 413a9a12-4ed0-41d0-8497-3698ff40941b : Cardio
- Nordic Hamstring Curl — 517569ba-2fb9-4dd9-a5fa-b86ee6e0fabf : legs
- Bloc plancher pelvien — 5ee34b7f-0e55-4125-a681-8a7def446441 : Cardio
- Intervalles (VO2) — 6db73454-2ed1-4ead-847c-a873e1588df9 : Cardio
- Skull Crusher (EZ) — 75c741f8-8ed6-4eb1-bf08-a45419908038 : arms
- Broad Jump — 941bd354-bb6a-421e-b86f-01d4176259c6 : Jambes
- Tibialis Raises — bbbcbcb3-6693-4111-9528-06b8f0d725d9 : legs
- Cossack Squat — c96cc070-d44c-44e4-9658-d40370ebf8e2 : legs
- 90/90 Hip + Band Shoulder Rotation — cdac5271-1a7a-4239-972a-fb6ebec1806c : Mobility
- World's Greatest Stretch — e13acf43-f687-4a63-93e9-0b6ab7ca9400 : Mobility

## Inventaire intégral et validation

- inventory.csv : 161 lignes avec tous les champs extraits, classifications et champs manquants. before.json et after.json : instantanés complets des colonnes auditées. Ambiguïtés et archivées intégralement inchangées.
- Écritures REST uniquement sur exercises, par UUID, avec compare-and-set des anciennes valeurs de chaque champ modifié. Relecture finale comparée à la projection exacte du plan. Aucun appel save_exercise/upsert pouvant toucher les prescriptions.
- Test qualité couvre toutes les lignes, identité/nom, principal scalaire, muscles connus, doublons/overlap, groupe/charge/cohérence. Le registre unresolved.json est comparé exactement pour détecter toute nouvelle anomalie. Ce test de non-régression ne signifie PAS que le catalogue est propre.
- Gate strict : `python3 scripts/audit_exercise_catalogue.py docs/audits/catalogue-2026-11-07/after.json` retourne **1** tant que les anomalies/taxonomies sont non résolues, avec nom et ID de chaque constat.
- Tests ciblés : test_exercise_catalogue_quality.py, test_landmine.py, test_analytics_adapter.py, test_muscle_workload_analytics.py ; 53 tests verts. Pas de full suite. Aucun changement Swift de cette tâche, pas de build iPhone nécessaire.
- Référence anatomique de contrôle : [ACE Applied Exercise Science](https://www.acefitness.org/academy/AcademyElitePDFs/ESS-AES_Download_Final.pdf), tableau des actions de l’épaule (deltoïde postérieur / rotation externe). La correction Face Pull repose aussi sur le nom explicite et l’autre Face Pull du catalogue. Aucune tentative d’inférer les variantes machine depuis une image non examinée.

## GIT

Fichiers de cette tâche : api/utils.py ; scripts/audit_exercise_catalogue.py ; tests/test_exercise_catalogue_quality.py ; docs/audits/catalogue-2026-11-07/*.
Changements dirty préexistants conservés (SmartAlarm, Programme et tests associés, projet Xcode). Aucun stage, commit, push ou déploiement. `git diff --check` réussi (exit 0) ; état final dans git-final.txt.

**STOP — catalogue taxonomy requires product decision before final normalization**
