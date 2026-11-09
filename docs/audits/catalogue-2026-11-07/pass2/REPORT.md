# CATALOGUE TAXONOMY — seconde passe

**GO CATALOGUE TAXONOMY — canonical broad groups and training-relevant muscle metadata are coherent across the complete catalogue; only genuinely ambiguous exercises remain isolated**

**Portée : code local et catalogue cible validés. Ce n’est pas un GO pour une production entièrement migrée.** Les valeurs nécessitant le nouveau backend/client restent dans pending.json ; aucun déploiement effectué. Le gate brut en production garde des erreurs connues, détaillées ci-dessous.

## CATALOGUE

| Mesure | Nombre |
|---|---:|
| total | 161 |
| active | 142 |
| archived | 19 |
| corrected_first_pass | 94 |
| corrected_second_pass_production | 125 |
| fields_second_pass_production | 367 |
| candidate_rows_changed | 148 |
| pending_rows | 65 |
| pending_active_rows | 46 |
| resolved_initial_ambiguities | 5 |
| remaining_ambiguous | 13 |

Les 125 corrections de seconde passe recoupent celles de première passe : ne pas additionner 94 + 125. Les 19 archivées n’ont reçu aucune écriture. Le candidat normalise leurs valeurs renseignées ; les données historiques manquantes sont tolérées et listées séparément.

## TAXONOMY

Contrat inchangé : primary = muscle_specific scalaire, fallback muscle_group ; secondary_muscles est le tableau des synergistes. Aucun champ primary_muscles ajouté, aucun ID recréé. Les groupes servent au reporting, les cibles détaillées aux analyses. Les portions anatomiques déjà proposées et utilisées restent compatibles, sans créer de nouvelles portions.

Canonique partagé : api/exercise_taxonomy_data.py, module pur api/exercise_taxonomy.py et vocabulaire Swift généré dans Models/MuscleMapping.swift. La parité est testée.

### Groupes et muscles détaillés canoniques

| Groupe large | Cibles détaillées acceptées |
|---|---|
| Pectoraux | Pectoral majeur, Pectoral supérieur, Pectoral moyen, Pectoral inférieur, Pectoral mineur, Serratus antérieur, Pectoraux |
| Dos | Haut du dos, Grand dorsal, Rhomboïdes, Grand rond, Érecteurs du rachis, Multifides, Dos |
| Épaules | Deltoïdes, Coiffe des rotateurs, Deltoïde antérieur, Deltoïde médial, Deltoïde postérieur, Sous-épineux, Supra-épineux, Sous-scapulaire, Petit rond, Épaules |
| Triceps | Triceps — longue portion, Triceps — chef latéral, Triceps — chef médial, Anconé, Triceps |
| Quadriceps | Quadriceps, Vaste latéral, Vaste médial, Vaste intermédiaire, Droit fémoral |
| Ischio-jambiers | Ischio-jambiers, Biceps fémoral, Biceps fémoral — longue portion, Biceps fémoral — courte portion, Semi-tendineux, Semi-membraneux |
| Fessiers | Grand fessier, Moyen fessier, Petit fessier, Tenseur du fascia lata, Fessiers |
| Mollets | Gastrocnémien, Gastrocnémien — chef médial, Gastrocnémien — chef latéral, Soléaire, Tibial antérieur, Mollets |
| Core | Obliques, Plancher pelvien, Droit abdominal, Oblique externe, Oblique interne, Transverse de l'abdomen, Carré des lombes, Psoas |
| Hanches | Adducteurs, Fléchisseurs de hanche, Grand adducteur, Long adducteur, Court adducteur, Gracile, Pectiné |
| Cou | Sterno-cléido-mastoïdien, Splénius, Cou |
| Autre | Aucune cible anatomique obligatoire |
| Biceps | Brachial, Biceps brachial — longue portion, Biceps brachial — courte portion, Biceps |
| Avant-bras | Brachioradialis, Supinateur, Fléchisseurs du poignet, Extenseurs du poignet, Fléchisseurs des doigts, Avant-bras |
| Trapèzes | Trapèze supérieur, Trapèze moyen, Trapèze inférieur, Trapèzes |

Les groupes Biceps/Triceps sont aussi les noms génériques des cibles ; Biceps brachial/Triceps brachial sont des alias, pas deux nouvelles lignes de volume. Pectoraux/Fessiers/Mollets restent des cibles génériques valides, distinctes des muscles spécifiques. Hanches existait déjà dans l’éditeur : aucun nouveau groupe Adducteurs/Hip Flexors créé.

Exceptions non-force explicites : Thoracique, Hanches et Système cardiovasculaire sont des régions/systèmes, pas des muscles de force. Aucun seuil MEV/MAV inventé pour Hanches, Autre ou Cou. Ces cibles restent visibles dans les analytics détaillés et en texte si la silhouette ne les représente pas.

### Patterns

push_horizontal, push_vertical, pull_horizontal, pull_vertical, squat, hinge, unilateral_leg, press_machine, isolation_arm, isolation_shoulder, isolation_leg, core, rotation, carry, cardio, accessory_wrist, other.

Aucun nouvel enum : 17 patterns existants conservés. Hip Hinge/Hip Extension → hinge ; Horizontal/Vertical Push/Pull → clés snake_case ; Elbow Flexion/Extension → isolation_arm ; Hip Abduction → isolation_leg ; Lunge → unilateral_leg. Isolation est résolu selon le groupe. Plyometric n’est pas normalisé globalement : Box/Broad/Jump Squat → squat, Lateral Bound → unilateral_leg, Jump Shrug → hinge ; tracking_type=plyo reste inchangé.

### Équipement et charge

Équipements : Barre, Haltères, Machine, Câble, Bandes, Poids du corps, Smith Machine, TRX, Autre, bench, incline_bench, neck harness, plate, medicine ball, handle, box, bike, rower, nordic_bench, partner, ez_bar, wall, dip_bars, weight_belt.

Les accessoires déjà présents dans les seeds (bench, medicine ball, etc.) deviennent sélectionnables sans les faire passer pour de nouvelles conventions de charge. Autre est conservé pour les accessoires non nommés dans l’ancien choix (ab wheel/wrist roller). Les alternatives déclarées telles que Barre/TRX restent des alternatives, pas un inventaire supposé des équipements disponibles.

Types de charge : landmine, barbell, dumbbell, cable_single, cable_double, press, fixed_weight, bodyweight, endurance, machine.

Corrections weight_type limitées aux appareils/modalités explicites : cable_single pour Cable External Rotation, dumbbell pour Prone Y-T-W, barbell pour Skull Crusher, bodyweight pour Nordic/Cossack/Tibialis/Weighted Dips. Le champ legacy type, bar_weight, increment, tracking_type et tous les calculs de charge restent inchangés. Weighted Dips est confirmé par consigne de buste incliné + programme Pecs + type bodyweight préexistant.

### Alias normalisés / compatibilité

| Alias | Canonique |
|---|---|
| Abdominaux | Droit abdominal |
| glutes | Fessiers |
| Biceps+Avant-bras | Biceps |
| Gainage | Core |
| Pectoral majeur — chef claviculaire | Pectoral supérieur |
| Pectoral majeur — chef sternal | Pectoral moyen |
| Pectoral majeur — chef costal | Pectoral inférieur |
| Droit de l'abdomen | Droit abdominal |
| Droit de l’abdomen | Droit abdominal |
| Brachialis | Brachial |
| Trapèze — chef supérieur | Trapèze supérieur |
| Trapèze — chef moyen | Trapèze moyen |
| Trapèze — chef inférieur | Trapèze inférieur |
| Hip Flexors | Fléchisseurs de hanche |
| hip flexors | Fléchisseurs de hanche |
| hip_flexors | Fléchisseurs de hanche |
| adductors | Adducteurs |
| tibialis_anterior | Tibial antérieur |
| rectus_abdominis | Droit abdominal |
| rectus abdominis | Droit abdominal |
| chest | Pectoraux |
| pectorals | Pectoraux |
| pecs | Pectoraux |
| upper chest | Pectoral supérieur |
| lower chest | Pectoral inférieur |
| lower_chest | Pectoral inférieur |
| back | Dos |
| lats | Grand dorsal |
| upper back | Haut du dos |
| rhomboids | Rhomboïdes |
| lower back | Érecteurs du rachis |
| traps | Trapèzes |
| trapezius | Trapèzes |
| mid_traps | Trapèze moyen |
| shoulders | Épaules |
| deltoids | Deltoïdes |
| delts | Deltoïdes |
| front_delts | Deltoïde antérieur |
| anterior deltoid | Deltoïde antérieur |
| lateral deltoid | Deltoïde médial |
| rear delts | Deltoïde postérieur |
| rear_delts | Deltoïde postérieur |
| rear deltoid | Deltoïde postérieur |
| posterior deltoid | Deltoïde postérieur |
| rotator_cuff | Coiffe des rotateurs |
| triceps_long | Triceps — longue portion |
| triceps_lateral | Triceps — chef latéral |
| triceps_medial | Triceps — chef médial |
| forearms | Avant-bras |
| quads | Quadriceps |
| hamstrings | Ischio-jambiers |
| gluteus maximus | Grand fessier |
| gluteus medius | Moyen fessier |
| calves | Mollets |
| soleus | Soléaire |
| abs | Droit abdominal |
| neck | Cou |
| pelvic floor | Plancher pelvien |
| Biceps brachial | Biceps |
| Triceps brachial | Triceps |

La liste ci-dessus décrit le code local. Les écritures réelles sont exclusivement corrections.json ; tout ce qui requiert une valeur non comprise par le backend/client préexistant reste pending.json. Les anciens alias sont conservés dans les mappings, pas multipliés dans le catalogue cible. Les tableaux muscles[] et agrégations de volume héritées restent compatibles avec leurs règles historiques ; les distinctions détaillées sont portées par muscle_specific/secondary_muscles et le cockpit normalisé.

## 13 UNKNOWN GROUPS

Il s’agissait de **13 exercices portant 5 valeurs distinctes**, pas de 13 groupes à créer.

| Exercice / ID | Valeur initiale | Cible détaillée | Groupe canonique | Secondaires cibles | État DB | Raison |
|---|---|---|---|---|---|---|
| Thoracic Extension + Open Book / 112bc757-0b40-480c-9815-95064c0a81a9 | Mobility | Thoracique | Dos | ["Obliques"] | Appliqué | Thoracic region; non-strength mobility, not a strength attribution. |
| Cat-Cow + Thoracic Rotation / 18ae9f4c-94b4-4dab-b4be-4f2b64a3fe85 | Mobility | Thoracique | Dos | [] | Appliqué | Thoracic spine mobility; region retained as non-strength exception. |
| Box Jump / 3d10e32d-23a1-4168-8b9e-013beb210f57 | Jambes | Quadriceps | Quadriceps | ["Grand fessier", "Gastrocnémien"] | Appliqué | Existing explicit knee-extensor target; plyo remains unchanged. |
| Zone-2 (vélo/rameur) / 413a9a12-4ed0-41d0-8497-3698ff40941b | Cardio | Système cardiovasculaire | Autre | [] | Différé jusqu’au déploiement | Cardiorespiratory modality has no truthful skeletal muscle group; existing Autre bucket. |
| Nordic Hamstring Curl / 517569ba-2fb9-4dd9-a5fa-b86ee6e0fabf | legs | Ischio-jambiers | Ischio-jambiers | [] | Appliqué | Explicit eccentric knee flexion; no hip-hinge attribution. |
| Bloc plancher pelvien / 5ee34b7f-0e55-4125-a681-8a7def446441 | Cardio | Plancher pelvien | Core | [] | Appliqué | Pelvic-floor protocol is trunk/pelvic bucket, not cardiovascular. |
| Intervalles (VO2) / 6db73454-2ed1-4ead-847c-a873e1588df9 | Cardio | Système cardiovasculaire | Autre | [] | Différé jusqu’au déploiement | Cardiorespiratory modality; existing Autre bucket, no invented muscle. |
| Skull Crusher (EZ) / 75c741f8-8ed6-4eb1-bf08-a45419908038 | arms | Triceps — longue portion | Triceps | ["Triceps — chef latéral", "Triceps — chef médial"] | Appliqué | Elbow extension; existing supported head retained. |
| Broad Jump / 941bd354-bb6a-421e-b86f-01d4176259c6 | Jambes | Quadriceps | Quadriceps | ["Grand fessier", "Gastrocnémien"] | Appliqué | Existing primary knee-extensor target retained, glute/calf synergists. |
| Tibialis Raises / bbbcbcb3-6693-4111-9528-06b8f0d725d9 | legs | Tibial antérieur | Mollets | [] | Appliqué | Existing editor explicitly places Tibial antérieur under Mollets; broad lower-leg bucket, not an alias for gastrocnemius. |
| Cossack Squat / c96cc070-d44c-44e4-9658-d40370ebf8e2 | legs | Adducteurs | Hanches | ["Quadriceps", "Grand fessier"] | Différé jusqu’au déploiement | Existing Hanches editor bucket explicitly covers hip adductors; no new group. |
| 90/90 Hip + Band Shoulder Rotation / cdac5271-1a7a-4239-972a-fb6ebec1806c | Mobility | Hanches | Hanches | ["Épaules"] | Différé jusqu’au déploiement | Hip mobility region; shoulder remains secondary region, non-strength exception. |
| World's Greatest Stretch / e13acf43-f687-4a63-93e9-0b6ab7ca9400 | Mobility | Hanches | Hanches | ["Thoracique", "Ischio-jambiers"] | Différé jusqu’au déploiement | Hip-focused lunge mobility plus thoracic rotation; no invented individual hip muscle. |

Copenhagen Plank, hors des 13, est aussi réévalué : Adducteurs → groupe Hanches dans le candidat, Obliques secondaire. Tibialis utilise la convention régionale existante de l’éditeur (Mollets englobe Tibial antérieur), sans assimiler le tibial au gastrocnémien. Son nom détaillé demeure visible.

## Réaudit de la première passe

Les 94 exercices ont été revus : first-pass-review.json contient chaque ID, les champs de première passe et leur état cible. Les équipements explicitement établis, variantes unilatérales et correction du Face Pull sont conservés. Meadows Row conserve landmine/landmine/45 et son tirage horizontal. Les nouvelles contradictions Overhead Press, Weighted Crunch et Goblet Squat sont gelées dans leur état de début de seconde passe, sans annuler arbitrairement les corrections précédentes.

Les secondaires ont été limités aux synergistes significatifs : triceps/deltoïde antérieur des presses, biceps/rhomboïdes des rows, fessiers des squats, fessiers/érecteurs sur les hinges chargés. Les listes de petits stabilisateurs cervicaux ne sont pas reproduites ; les isolations peuvent avoir une liste vide. Les adducteurs, obliques, brachial, tibial et fléchisseurs de hanche gardent leur distinction utile.

Les curl machines restent classés flexion du genou/ischio-jambiers sans inventer un chef dominant ; le gastrocnémien est un synergiste documenté ([NASM](https://www.nasm.org/resource-center/exercise-library/seated-leg-curl)). Le RDL garde son association ischio-jambiers/fessiers ([ACE](https://www.acefitness.org/continuing-education/certified/may-2025/8865/the-ace-do-it-better-series-the-romanian-deadlift/)).

## Ambiguïtés résolues

- **Leg Curl** : Hamstring knee flexion in machine, consistent across name/metadata and three programme usages; posture not needed for this granularity.
- **Single-Arm Triceps Extension** : Triceps extension, cable_single, one arm, Push B programme. Keep generic Triceps brachial rather than infer overhead angle.
- **Cable Fly / Pec Dec** : Explicit cable instructions and cable_double agree; catalogue entry is the cable variant, despite alternative in name.
- **Weighted Dips** : Forward lean instructions, lower-chest metadata and Pecs programme agree; existing bodyweight type defines additional-load contract.
- **Cossack Squat** : Bodyweight, reps, lateral squat instructions and unilateral flag agree; use existing Hanches group for explicit adductor target.

## AMBIGUOUS — 13 exercices entièrement inchangés dans cette passe

### Calf Raise — 1d8ed80c-702b-4d54-9d15-dd6eef47cb57

- Ambiguïté : Debout (gastrocnémien) ; assis (soléaire, image actuelle).
- Information manquante : Confirmer position du genou et machine.
- Usages examinés : New (strength, 3x12-15); Lundi AM — Jambes (strength, 4x8-12).
- Métadonnées : `{"id": "1d8ed80c-702b-4d54-9d15-dd6eef47cb57", "name": "Calf Raise", "type": "machine", "category": "legs", "pattern": "isolation", "level": "beginner", "default_scheme": "3x12-15", "load_profile": "isolation", "muscles": ["calves", "soleus"], "increment": 5.0, "bar_weight": 0.0, "tracking_type": "reps", "rest_seconds": 120, "tips": "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Seated_Calf_Raise/1.jpg", "muscle_group": "Mollets", "muscle_specific": "Gastrocnémien", "secondary_muscles": null, "movement_pattern": "Isolation", "weight_type": "machine", "equipment": null, "alternate_name": null, "is_unilateral": false, "deleted_at": null}`

### T-Bar Row — 28614b32-1508-4cb2-8b38-f6b051127e48

- Ambiguïté : Landmine libre ; machine T-bar avec support thoracique (image actuelle).
- Information manquante : Confirmer appareil et convention de charge.
- Usages examinés : Dimanche AM — Largeur dos + bras (strength, 3x8-10); Pull (strength, 3x8-12); Pull (strength, 3x8-12); Vendredi AM — Pull B (force, 4x6-10).
- Métadonnées : `{"id": "28614b32-1508-4cb2-8b38-f6b051127e48", "name": "T-Bar Row", "type": "barbell", "category": "pull", "pattern": "horizontal_pull", "level": "intermediate", "default_scheme": "4x8-10", "load_profile": "compound_hypertrophy", "muscles": ["lats", "rhomboids", "traps", "biceps"], "increment": 5.0, "bar_weight": 45.0, "tracking_type": "reps", "rest_seconds": 120, "tips": "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Lying_T-Bar_Row/1.jpg", "muscle_group": "Dos", "muscle_specific": "Grand dorsal", "secondary_muscles": ["Rhomboïdes"], "movement_pattern": "Horizontal Pull", "weight_type": "barbell", "equipment": null, "alternate_name": null, "is_unilateral": false, "deleted_at": null}`

### Burpee — 3546990d-0a44-46ba-a36b-7b551571c03b

- Ambiguïté : Avec pompe ; sans pompe ; variante avec saut.
- Information manquante : Séquence exacte avant attribution musculaire principale.
- Usages examinés : aucun usage dans les programmes interrogés.
- Métadonnées : `{"id": "3546990d-0a44-46ba-a36b-7b551571c03b", "name": "Burpee", "type": "bodyweight", "category": "core", "pattern": "mobility", "level": "intermediate", "default_scheme": "3x8-12", "load_profile": "compound_hypertrophy", "muscles": ["cardiovascular system", "quadriceps", "hamstrings", "calves", "shoulders", "chest"], "increment": 5.0, "bar_weight": 0.0, "tracking_type": "reps", "rest_seconds": 120, "tips": "Start in a standing position with your feet shoulder-width apart.. Lower your body into a squat position by bending your knees and placing your hands on the floor in front of you.", "muscle_group": "Pectoraux", "muscle_specific": "Pectoral moyen", "secondary_muscles": null, "movement_pattern": "Gainage", "weight_type": "bodyweight", "equipment": null, "alternate_name": null, "is_unilateral": false, "deleted_at": null}`

### Dumbbell Pull Over — 35ab117f-cd8e-4c71-b69b-f91f3676d818

- Ambiguïté : Pull-over haltère (nom) ; machine (type et équipement).
- Information manquante : Confirmer appareil réel, puis attribution pectoraux/dorsaux selon exécution.
- Usages examinés : Samedi Impro (strength, 3x8-12).
- Métadonnées : `{"id": "35ab117f-cd8e-4c71-b69b-f91f3676d818", "name": "Dumbbell Pull Over", "type": "machine", "category": "push", "pattern": "push", "level": "intermediate", "default_scheme": "3x8-12", "load_profile": "compound_hypertrophy", "muscles": ["back"], "increment": 5.0, "bar_weight": 0.0, "tracking_type": "reps", "rest_seconds": 120, "tips": null, "muscle_group": "Dos", "muscle_specific": "Grand dorsal", "secondary_muscles": ["Grand rond", "Pectoral majeur — chef costal", "Triceps — longue portion"], "movement_pattern": "push_vertical", "weight_type": "machine", "equipment": ["Machine"], "alternate_name": null, "is_unilateral": false, "deleted_at": null}`

### 6-Way Shoulder Raise — 48b9b47f-2f16-4053-aec1-1f75e5e20992

- Ambiguïté : Séquence élévations latérales/frontales ; séquence incluant rotation externe.
- Information manquante : Décrire les six phases et choisir attribution principale unique.
- Usages examinés : Upper A (strength, 3x6-10); 6ème bonus (strength, 3x6-10).
- Métadonnées : `{"id": "48b9b47f-2f16-4053-aec1-1f75e5e20992", "name": "6-Way Shoulder Raise", "type": "dumbbell", "category": "push", "pattern": "horizontal_push", "level": "intermediate", "default_scheme": "3x6-10", "load_profile": null, "muscles": ["rear delts", "rhomboids", "rotators", "shoulders", "traps"], "increment": 5.0, "bar_weight": 0.0, "tracking_type": "reps", "rest_seconds": null, "tips": null, "muscle_group": "Épaules", "muscle_specific": "Deltoïdes", "secondary_muscles": null, "movement_pattern": "Isolation", "weight_type": "dumbbell", "equipment": null, "alternate_name": null, "is_unilateral": false, "deleted_at": null}`

### Medicine Ball Overhead Throw — 6ad2001a-43b9-4546-9681-7140c04dda77

- Ambiguïté : Lancer vers l’avant au-dessus de la tête ; lancer arrière en triple extension.
- Information manquante : Direction du lancer et modalité de charge.
- Usages examinés : aucun usage dans les programmes interrogés.
- Métadonnées : `{"id": "6ad2001a-43b9-4546-9681-7140c04dda77", "name": "Medicine Ball Overhead Throw", "type": null, "category": null, "pattern": null, "level": null, "default_scheme": "4x5", "load_profile": null, "muscles": [], "increment": 5, "bar_weight": 0, "tracking_type": "plyo", "rest_seconds": null, "tips": null, "muscle_group": "Épaules", "muscle_specific": "Deltoïde antérieur", "secondary_muscles": null, "movement_pattern": "Plyometric", "weight_type": "endurance", "equipment": null, "alternate_name": null, "is_unilateral": false, "deleted_at": null}`

### Chest press — bd09ae7b-69df-4790-807e-b4f7b46baac4

- Ambiguïté : Presse horizontale ; presse inclinée (chef claviculaire actuel).
- Information manquante : Angle et modèle de machine.
- Usages examinés : Hôtel séance (strength, 3x8-12); Hôtel séance (strength, 3x8-12).
- Métadonnées : `{"id": "bd09ae7b-69df-4790-807e-b4f7b46baac4", "name": "Chest press", "type": "machine", "category": "push", "pattern": "push", "level": "beginner", "default_scheme": "3x8-12", "load_profile": "compound_hypertrophy", "muscles": ["chest"], "increment": 5.0, "bar_weight": 0.0, "tracking_type": "reps", "rest_seconds": null, "tips": null, "muscle_group": "Pectoraux", "muscle_specific": "Pectoral majeur — chef claviculaire", "secondary_muscles": ["Deltoïde antérieur", "Triceps — chef latéral", "Triceps — chef médial"], "movement_pattern": "push_horizontal", "weight_type": "machine", "equipment": ["Machine"], "alternate_name": null, "is_unilateral": false, "deleted_at": null}`

### Wide-Grip Cable Row — bdc9b9c7-a501-47d4-a414-ada214f5514b

- Ambiguïté : Poulie à pile unique ; machine à bras indépendants.
- Information manquante : Confirmer convention machine/câble et trajectoire.
- Usages examinés : Mardi AM — Pull A (strength, 3x8-12).
- Métadonnées : `{"id": "bdc9b9c7-a501-47d4-a414-ada214f5514b", "name": "Wide-Grip Cable Row", "type": "machine", "category": "pull", "pattern": "pull", "level": "", "default_scheme": "3x8-12", "load_profile": null, "muscles": ["back"], "increment": 5.0, "bar_weight": 0.0, "tracking_type": "reps", "rest_seconds": null, "tips": null, "muscle_group": "Dos", "muscle_specific": "Grand dorsal", "secondary_muscles": ["Rhomboïdes", "Trapèze — chef inférieur", "Trapèze — chef moyen"], "movement_pattern": "pull_horizontal", "weight_type": "machine", "equipment": ["Machine"], "alternate_name": null, "is_unilateral": false, "deleted_at": null}`

### Sandbag Bear Hug Squat — c6b79878-6a18-4de2-a4d0-26b65ed069fe

- Ambiguïté : Sandbag tenu contre soi ; machine press (type actuel).
- Information manquante : Confirmer appareil et type de charge supporté pour sandbag.
- Usages examinés : Dimanche PM — Jambes B (isolation, 3x6-10).
- Métadonnées : `{"id": "c6b79878-6a18-4de2-a4d0-26b65ed069fe", "name": "Sandbag Bear Hug Squat", "type": "press", "category": "legs", "pattern": "squat", "level": "intermediate", "default_scheme": "3x6-10", "load_profile": "compound_heavy", "muscles": ["quads"], "increment": 5.0, "bar_weight": 0.0, "tracking_type": "reps", "rest_seconds": 120, "tips": null, "muscle_group": "Quadriceps", "muscle_specific": null, "secondary_muscles": ["Biceps fémoral — longue portion", "Grand adducteur", "Grand fessier"], "movement_pattern": "squat", "weight_type": "press", "equipment": [], "alternate_name": null, "is_unilateral": false, "deleted_at": null}`

### Cable Crunch — f27c51f6-99a3-4aac-956a-90f385a5423e

- Ambiguïté : Une pile ; deux piles (weight_type actuel, type cable).
- Information manquante : Confirmer nombre de piles et convention de saisie.
- Usages examinés : Dimanche PM — Jambes B (core, 3x12-15); 6ème bonus (strength, 3x12-15); Dimanche PM — Puissance + bras + core (strength, 3x12-15).
- Métadonnées : `{"id": "f27c51f6-99a3-4aac-956a-90f385a5423e", "name": "Cable Crunch", "type": "cable", "category": "strength", "pattern": "core", "level": "beginner", "default_scheme": "3x12-15", "load_profile": "isolation", "muscles": ["core"], "increment": 2.5, "bar_weight": 0, "tracking_type": "reps", "rest_seconds": 60, "tips": "À genoux, fléchissez la colonne (pas les hanches). Contraction maximale au bas. Coudes fixes.", "muscle_group": "Core", "muscle_specific": "Droit abdominal", "secondary_muscles": ["Obliques"], "movement_pattern": "Gainage", "weight_type": "cable_double", "equipment": ["câble"], "alternate_name": "Crunch Poulie", "is_unilateral": false, "deleted_at": null}`

### Overhead Press — b95a3324-7813-4d73-b0de-6e20867b0983

- Ambiguïté : See conflicting implement metadata and instructions.
- Information manquante : Instructions specify barbell while both load fields specify dumbbell and bar_weight=45. Confirm actual implement; no load convention changed.
- Usages examinés : aucun usage dans les programmes interrogés.
- Métadonnées : `{"id": "b95a3324-7813-4d73-b0de-6e20867b0983", "name": "Overhead Press", "type": "dumbbell", "category": "push", "pattern": "vertical_push", "level": "intermediate", "default_scheme": "3x8-10", "load_profile": "compound_heavy", "muscles": ["anterior deltoid", "traps", "triceps"], "increment": 5.0, "bar_weight": 45.0, "tracking_type": "reps", "rest_seconds": 120, "tips": "Debout · barre · core engagé · poignets neutres", "muscle_group": "Épaules", "muscle_specific": "Deltoïde antérieur", "secondary_muscles": null, "movement_pattern": "Vertical Push", "weight_type": "dumbbell", "equipment": ["Haltères"], "alternate_name": null, "is_unilateral": false, "deleted_at": null}`

### Weighted Crunch — e0eeb2d6-092f-4b87-836a-fb24093ddcf8

- Ambiguïté : See conflicting implement metadata and instructions.
- Information manquante : Instructions specify plate/dumbbell on chest, both load fields specify cable. Confirm implement and intended variant.
- Usages examinés : aucun usage dans les programmes interrogés.
- Métadonnées : `{"id": "e0eeb2d6-092f-4b87-836a-fb24093ddcf8", "name": "Weighted Crunch", "type": "cable", "category": "core", "pattern": "core", "level": "intermediate", "default_scheme": "3x8-12", "load_profile": "isolation", "muscles": ["abs", "obliques"], "increment": 5.0, "bar_weight": 0.0, "tracking_type": "reps", "rest_seconds": 120, "tips": "Lie flat on your back with your knees bent and feet flat on the ground.. Hold a weight plate or dumbbell on your chest.", "muscle_group": "Core", "muscle_specific": "Droit abdominal", "secondary_muscles": null, "movement_pattern": "Gainage", "weight_type": "cable_single", "equipment": ["Câble"], "alternate_name": null, "is_unilateral": false, "deleted_at": null}`

### Goblet Squat — c9a0be3d-6761-4957-873d-a1b32f94ed8f

- Ambiguïté : See conflicting implement metadata and instructions.
- Information manquante : Instructions specify kettlebell, type/equipment specify dumbbell. Confirm implement before replacing first-pass equipment.
- Usages examinés : aucun usage dans les programmes interrogés.
- Métadonnées : `{"id": "c9a0be3d-6761-4957-873d-a1b32f94ed8f", "name": "Goblet Squat", "type": "dumbbell", "category": "legs", "pattern": "squat", "level": "beginner", "default_scheme": "4x12", "load_profile": "compound_hypertrophy", "muscles": ["quadriceps", "fessiers"], "increment": 5.0, "bar_weight": 0.0, "tracking_type": "reps", "rest_seconds": 120, "tips": "Kettlebell · talons surélevés · genoux ouverts", "muscle_group": "Quadriceps", "muscle_specific": "Quadriceps", "secondary_muscles": null, "movement_pattern": "Squat", "weight_type": "dumbbell", "equipment": ["Haltères"], "alternate_name": null, "is_unilateral": false, "deleted_at": null}`

## QUALITY GATE

Le test global examine **161 exercices**, y compris les taxonomies des archivées. Les erreurs ci-dessous sont des constats, pas des exceptions silencieuses. Une nouvelle erreur hors des 13 IDs ambigus fait échouer les tests ; les lignes ambiguës sont comparées intégralement au snapshot initial. Aucun simple registre de défauts préexistants ne remplace cette validation.

| Contrôle (actifs) | Production finale | Candidat local, ambiguïtés incluses | Candidat hors ambiguïtés |
|---|---:|---:|---:|
| missing_primary | 0 | 0 | 0 |
| unknown_group | 5 | 0 | 0 |
| unknown_muscle | 6 | 4 | 0 |
| overlap | 0 | 0 | 0 |
| duplicate_secondary | 0 | 0 | 0 |
| invalid_primary | 0 | 0 | 0 |
| invalid_pattern | 9 | 9 | 0 |
| invalid_load | 0 | 0 | 0 |
| invalid_equipment | 1 | 1 | 0 |
| missing_equipment | 9 | 6 | 0 |
| incompatible_group | 2 | 0 | 0 |

`unknown_muscle` inclut les libellés non canoniques encore présents dans une ligne ambiguë, même si leur alias est connu. La validation n’invente pas de principal pour Sandbag : son groupe Quadriceps constitue le fallback principal déjà prévu au modèle. Primary est scalaire, donc un tableau/duplicata de primary est invalide.

Archivées : production {"invalid_pattern": 18, "unknown_group": 1, "incompatible_group": 1, "unknown_muscle": 2} ; candidat {}. Lacunes historiques séparées dans archived-missing-legacy.json ; aucune mutation des archivées en DB.

Commande stricte : `python3 scripts/audit_exercise_catalogue.py <snapshot.json>`. Exit 1 sur production ET candidat brut, car le candidat brut conserve les ambiguïtés. Le test catalogue cible exige zéro anomalie hors des seules lignes gelées ; il vérifie aussi que toutes les cibles canoniques survivent dans les analytics. Le script legacy est uniquement la reproduction figée de la première passe.

## DOWNSTREAM

| Consommateur | Résultat |
|---|---|
| Stats / analytics_adapter | detailed_target conserve front/side/rear delts, lats/haut du dos/traps, abs/obliques ; les alias exacts fusionnent. Tous les muscles canoniques testés ; inconnu visible, pas supprimé. Un groupe secondaire englobant le principal est dédupliqué ; Brachial et Biceps restent distincts malgré leur bucket commun. |
| Volume / muscle_volume | Alias exacts fusionnés avant agrégation, mêmes sets bruts ; pas de réécriture de logs. Le modèle MEV large reste distinct du détail, aucun nouveau seuil. Dans le cockpit, une sous-région ne reçoit pas automatiquement le seuil du groupe entier : repère absent explicite, sauf cibles possédant déjà leur propre repère (grand dorsal/arrière d’épaule). |
| Doctrine | Groupes existants Hanches/Autre explicitement hors seuils ; Cou reste exclu. Avant-bras conserve la fusion doctrinale préexistante Biceps, mais les cibles détaillées ne sont pas fusionnées dans workload. |
| Silhouette / rapports | Les cibles sans zone V1 dédiée sont rendues en texte dans Dashboard et rapports de séance ; aucune fausse zone anatomique ajoutée. |
| Programme / Day Composer | Aucune affectation/prescription/planning modifié ; lecture des programmes uniquement pour les ambiguïtés. Chargement catalogue normalise les alias, jamais les IDs/schemes/charges. |
| Inventaire / filtres | Choix générés depuis le même contrat ; cardio visible dans filtres ; endurance couvre time/cardio/interval. Les modalités non-force ne sont plus forcées à time lors d’une édition. |
| ExerciseCard | Aucun calcul ni modèle de logs modifié ; is_unilateral explicite sur Single-Arm Triceps Extension, les autres corrections unilatérales de première passe restent. |
| Progression | type, bar_weight, increment, load_profile, historiques inchangés ; Landmine testé. Aucun algorithme de progression changé. |
| Recherche | Noms/alternate_name/IDs intégralement conservés ; recherche et références par nom inchangées. |
| DNA | Les alias de patterns sont résolus avant les ratios existants ; aucun nouveau pattern inventé. |

## Corrections de production — avant → après

### Copenhagen Plank — 00332b97-110a-4915-b17a-4e2e49919e6d

- secondary_muscles : ["Obliques", "Core"] → ["Obliques"]
- category : "core" → "legs"
- movement_pattern : "Gainage" → "core"

### Hollow Body Crunch — 0372093b-e1ff-4706-9863-82c82491a43b

- secondary_muscles : ["Obliques", "Hip Flexors"] → ["Obliques"]
- category : "strength" → "core"
- movement_pattern : "Gainage" → "core"

### Inverted Row — 0490140d-dfe8-4fe1-8463-90ffc2c93eab

- movement_pattern : "Horizontal Pull" → "pull_horizontal"
- equipment : null → ["Barre", "TRX"]
- pattern : "horizontal_pull" → "pull"

### Neck Curl — 10254163-84fd-4bd6-8187-132c40992e72

- secondary_muscles : ["longus capitis", "longus colli", "scalenes"] → []
- movement_pattern : "pull_vertical" → "other"

### Romanian Deadlift — 10b42a6a-497c-42a9-a84a-45b2deacba3b

- muscle_specific : "Biceps fémoral" → "Ischio-jambiers"
- movement_pattern : "Hip Hinge" → "hinge"

### Thoracic Extension + Open Book — 112bc757-0b40-480c-9815-95064c0a81a9

- category : "strength" → "mobility"
- movement_pattern : "Rotation" → "rotation"
- equipment : null → []
- muscle_group : "Mobility" → "Dos"

### Chest-Supported DB Row — 11b465db-21c9-418e-ae02-67a00e447a85

- movement_pattern : "Horizontal Pull" → "pull_horizontal"
- pattern : "horizontal_pull" → "pull"

### Barbell Close-Grip Bench Press — 148511ac-237c-432d-accb-1b5ebfe046a1

- muscle_specific : "Triceps brachial" → "Triceps"
- movement_pattern : "Horizontal Push" → "push_horizontal"
- pattern : "horizontal_push" → "push"

### Single-Arm Triceps Extension — 1519b8a5-c80a-44a9-83e1-d23a4a90437e

- muscle_specific : "Triceps — longue portion" → "Triceps"
- category : "pull" → "push"
- movement_pattern : "pull_vertical" → "isolation_arm"
- equipment : [] → ["Câble"]
- is_unilateral : false → true
- pattern : "pull" → "isolation"

### Leg Extension — 1639cf6d-8235-4e99-8bee-35d33b9911dc

- secondary_muscles : null → []
- movement_pattern : "Isolation" → "isolation_leg"

### Cat-Cow + Thoracic Rotation — 18ae9f4c-94b4-4dab-b4be-4f2b64a3fe85

- secondary_muscles : null → []
- category : null → "mobility"
- movement_pattern : "Rotation" → "rotation"
- equipment : null → []
- muscle_group : "Mobility" → "Dos"
- pattern : null → "mobility"

### Medicine Ball Rotational Throw — 1efbb1ab-ce90-4a8c-8755-8aa2ae085c61

- secondary_muscles : ["Core", "Épaules"] → []
- movement_pattern : "Rotation" → "rotation"

### Barbell Preacher Curl — 1f50f894-679d-427a-8ffc-fcd013dec943

- secondary_muscles : null → []
- muscle_specific : "Biceps brachial" → "Biceps"
- movement_pattern : "Elbow Flexion" → "isolation_arm"
- pattern : "vertical_pull" → "isolation"

### Unilateral lateral raises — 23c31a4a-84de-471d-9e0e-742920ae474a

- secondary_muscles : null → []
- movement_pattern : "Isolation" → "isolation_shoulder"
- pattern : "vertical_push" → "isolation"

### Lying Leg Curl — 2469a72a-0fed-4fe9-8287-0a48ea8cd033

- muscle_specific : "Biceps fémoral" → "Ischio-jambiers"
- movement_pattern : "Isolation" → "isolation_leg"
- pattern : "hinge" → "isolation"

### Hammer Curl — 290eb168-e05b-481f-9ef3-07051d6cbff0

- secondary_muscles : [] → ["Brachioradialis", "Biceps"]
- category : "" → "pull"
- movement_pattern : "Elbow Flexion" → "isolation_arm"

### Lateral Bound — 29153cb0-2fa5-4e66-bfc4-93b6c5914f23

- category : null → "legs"
- movement_pattern : "Plyometric" → "unilateral_leg"
- equipment : null → ["Poids du corps"]
- pattern : null → "lunge"

### Hip Thrust — 29609082-555f-40eb-b3a8-bc01efe793f2

- movement_pattern : "Hip Extension" → "hinge"

### Leg Curl — 2ae311da-6f2b-4683-b93a-81bd20b23e94

- muscle_specific : "Biceps fémoral" → "Ischio-jambiers"
- movement_pattern : "Isolation" → "isolation_leg"
- equipment : null → ["Machine"]
- pattern : "hinge" → "isolation"

### Barbell Curl — 2e0827c6-05ad-486e-95b1-e40d0f4bc022

- secondary_muscles : null → []
- muscle_specific : "Biceps brachial" → "Biceps"
- movement_pattern : "Elbow Flexion" → "isolation_arm"
- pattern : "vertical_pull" → "isolation"

### Cable Curl — 2e69ba02-e925-4865-8cea-31cfaf108d10

- secondary_muscles : null → []
- muscle_specific : "Biceps brachial" → "Biceps"
- movement_pattern : "Elbow Flexion" → "isolation_arm"

### Cable Lateral Raise — 2f717ae8-72cb-4a3f-8324-a980f6b7ab6a

- category : "" → "push"
- movement_pattern : "Isolation" → "isolation_shoulder"

### Pallof Press — 308b33e0-78b2-4a21-9810-e6559f0e3807

- secondary_muscles : ["Épaules"] → []
- category : "strength" → "core"
- movement_pattern : "Gainage" → "core"

### Band Pull-Apart — 36b22489-efaf-4358-a862-ebe1f813c68d

- secondary_muscles : null → []
- category : null → "mobility"
- movement_pattern : "Horizontal Pull" → "pull_horizontal"
- equipment : null → []
- pattern : null → "mobility"

### Bayesian Biceps Curl — 38bebfbe-036e-4023-a4db-12863ace35ed

- secondary_muscles : null → []
- muscle_specific : "Biceps brachial" → "Biceps"
- movement_pattern : "Elbow Flexion" → "isolation_arm"
- pattern : "vertical_pull" → "isolation"

### Cable External Rotation — 3af0d483-cc9e-433c-9a21-3a86c549e77e

- weight_type : "hypertrophy" → "cable_single"
- category : "shoulders" → "push"
- pattern : "rotation" → "core"

### Back Squat — 3b4b4a2f-4bf3-4526-bbaa-e4af98c0884a

- movement_pattern : "Squat" → "squat"

### EZ Bar Curl — 3b6c646a-133d-4618-9680-387786037816

- secondary_muscles : null → []
- muscle_specific : "Biceps brachial" → "Biceps"
- movement_pattern : "Elbow Flexion" → "isolation_arm"

### Box Jump — 3d10e32d-23a1-4168-8b9e-013beb210f57

- movement_pattern : "Plyometric" → "squat"
- muscle_group : "Jambes" → "Quadriceps"

### Abs wheel — 3d29d57a-7b3d-4e16-b87b-854651f94d68

- secondary_muscles : null → []
- movement_pattern : "Gainage" → "core"
- equipment : null → ["Autre"]

### Incline DB Press — 3dd16c0e-5082-4950-a645-1db789171655

- secondary_muscles : [] → ["Triceps", "Deltoïde antérieur"]
- category : "" → "push"
- movement_pattern : "Horizontal Push" → "push_horizontal"
- pattern : "isolation" → "push"

### Incline Cable Fly — 3eb47bc0-8e10-49f0-a4b8-2914db648503

- category : "" → "push"
- movement_pattern : "Horizontal Push" → "push_horizontal"
- pattern : "isolation" → "push"

### Barbell Shrug — 3ff53dd3-caaf-4b29-bc97-21fbf66cdc84

- secondary_muscles : null → []
- movement_pattern : "Isolation" → "isolation_shoulder"
- pattern : "horizontal_pull" → "isolation"

### Dumbbell Decline Bench Press — 4024dde6-3c2c-4463-9935-9c74c7f63545

- secondary_muscles : null → ["Triceps", "Deltoïde antérieur"]
- movement_pattern : "Horizontal Push" → "push_horizontal"
- pattern : "horizontal_push" → "push"

### Wrist Roller — 402e4fd4-1c97-413f-8f7b-5e2e1c4faf65

- secondary_muscles : null → []
- movement_pattern : "Isolation" → "accessory_wrist"
- equipment : null → ["Autre"]
- pattern : "horizontal_pull" → "isolation"

### Zone-2 (vélo/rameur) — 413a9a12-4ed0-41d0-8497-3698ff40941b

- movement_pattern : "Cardio" → "cardio"

### Barbell Jump Shrug — 45fb8027-6c8a-4104-9729-78e168056b30

- secondary_muscles : null → []
- category : null → "pull"
- movement_pattern : "Plyometric" → "hinge"
- equipment : null → ["Barre"]
- pattern : null → "hinge"

### Barbell Glute Bridge — 46dfd5a9-b52b-4690-ac22-b9064650f9eb

- secondary_muscles : null → []
- movement_pattern : "Hip Extension" → "hinge"

### Dips — 486b1277-3d39-4ac4-8247-b2b833ec03a8

- secondary_muscles : null → []
- muscle_specific : "Triceps brachial" → "Triceps"
- movement_pattern : "Vertical Push" → "push_vertical"
- pattern : "vertical_push" → "push"

### Cable Pull-Through — 4f44fe97-2dd0-400f-a653-b6d91c3964b7

- movement_pattern : "Hip Hinge" → "hinge"

### Nordic Hamstring Curl — 517569ba-2fb9-4dd9-a5fa-b86ee6e0fabf

- secondary_muscles : ["Fessiers", "Mollets"] → []
- weight_type : "strength" → "bodyweight"
- movement_pattern : "hinge" → "isolation_leg"
- muscle_group : "legs" → "Ischio-jambiers"
- pattern : "hinge" → "isolation"

### Sissy Squat — 578c78d5-c413-4827-a3d9-ef044359049f

- secondary_muscles : null → []
- movement_pattern : "Squat" → "squat"
- equipment : null → ["Poids du corps"]
- pattern : "isolation" → "squat"

### Deep Barbell Squat — 5d26346d-6eb6-4d48-8790-7171a6d1e284

- movement_pattern : "Squat" → "squat"

### Seated Cable Row — 5ea88c96-99b5-4a75-93a7-4d07ab68d9e9

- movement_pattern : "Horizontal Pull" → "pull_horizontal"
- pattern : "horizontal_pull" → "pull"

### Machine Rear Delt Flys — 5ed9acb6-76d6-408c-9aca-db573e1fb9dc

- secondary_muscles : null → []
- movement_pattern : "Horizontal Pull" → "pull_horizontal"
- pattern : "horizontal_pull" → "pull"

### Bloc plancher pelvien — 5ee34b7f-0e55-4125-a681-8a7def446441

- movement_pattern : "Cardio" → "core"
- muscle_group : "Cardio" → "Core"

### Lateral Raise — 5fe28d3e-6085-42c3-8973-d29f73766b55

- secondary_muscles : null → []
- movement_pattern : "Isolation" → "isolation_shoulder"

### Cable Seated Row — 60017691-bc43-4eaa-86d8-c0844621b6ab

- movement_pattern : "Horizontal Pull" → "pull_horizontal"
- pattern : "horizontal_pull" → "pull"

### Barbell Front Squat — 61ef73eb-53e4-464a-ae0f-bf2324d2fedb

- movement_pattern : "Squat" → "squat"

### Lat Pulldown — 62f5d842-4cb6-4142-9287-5a9757ae3caf

- secondary_muscles : null → ["Biceps"]
- movement_pattern : "Vertical Pull" → "pull_vertical"
- pattern : "vertical_pull" → "pull"

### Dumbbell Front Raise — 6722c8ed-08df-43ee-95c8-a02bb4fa57e3

- secondary_muscles : null → []
- movement_pattern : "Isolation" → "isolation_shoulder"

### Abductor machine — 690a10d1-d233-4318-93dc-5d40b053a018

- category : "" → "legs"
- movement_pattern : "Hip Abduction" → "isolation_leg"

### Incline DB Curl — 6b30f586-d5e6-4a41-9f28-56b9296dbea3

- secondary_muscles : null → []
- muscle_specific : "Biceps brachial" → "Biceps"
- movement_pattern : "Elbow Flexion" → "isolation_arm"

### Intervalles (VO2) — 6db73454-2ed1-4ead-847c-a873e1588df9

- movement_pattern : "Cardio" → "cardio"

### Rear Delt Cable Fly — 71eefa04-2eba-472e-981c-fc3a3ff01eb8

- secondary_muscles : null → []
- movement_pattern : "Horizontal Pull" → "pull_horizontal"
- pattern : "isolation" → "pull"

### Dumbbell Fly — 733f7dc8-fc2b-412d-bad2-e4d3b4c2b6fa

- secondary_muscles : null → []
- movement_pattern : "Horizontal Push" → "push_horizontal"
- pattern : "horizontal_push" → "push"

### Seated Calf Raise — 7381bd5d-dac0-4770-8873-4602ed8ed07e

- secondary_muscles : null → []
- movement_pattern : "Isolation" → "isolation_leg"

### Skull Crusher (EZ) — 75c741f8-8ed6-4eb1-bf08-a45419908038

- weight_type : "strength" → "barbell"
- movement_pattern : "push_horizontal" → "isolation_arm"
- muscle_group : "arms" → "Triceps"
- pattern : "push_horizontal" → "isolation"

### Dumbbell Hammer Curl — 781b2807-39ee-44e2-a783-084d41c8be1d

- secondary_muscles : null → ["Brachioradialis", "Biceps"]
- movement_pattern : "Elbow Flexion" → "isolation_arm"
- pattern : "vertical_pull" → "isolation"

### Bench Press — 78d5bcfc-2142-4dbd-a432-cf7921cf6c99

- secondary_muscles : ["Deltoïde antérieur"] → ["Triceps", "Deltoïde antérieur"]
- movement_pattern : "Horizontal Push" → "push_horizontal"
- pattern : "horizontal_push" → "push"

### Lateral Raises (un bras) — 78ed636f-c24a-4136-9d3b-f5317dff351f

- secondary_muscles : null → []
- movement_pattern : "Isolation" → "isolation_shoulder"

### Overhead Triceps Extension — 79bd63ce-e625-4e18-a7cd-aee68cc6f3fe

- secondary_muscles : null → []
- muscle_specific : "Triceps brachial" → "Triceps"
- movement_pattern : "Elbow Extension" → "isolation_arm"
- pattern : null → "isolation"

### Single-Arm Lat Pulldown — 7d4bbd9f-60fd-4851-bd19-4dcfb00023f6

- secondary_muscles : [] → ["Biceps"]

### Jump Squat — 85313d3e-abab-484d-85e1-3a2700fdaed4

- movement_pattern : "Plyometric" → "squat"
- equipment : null → ["Poids du corps"]
- pattern : "hinge" → "squat"

### Spider Curl — 86bb5979-dd4b-47e4-9ec1-829f8125a76e

- secondary_muscles : null → []
- muscle_specific : "Biceps brachial" → "Biceps"
- movement_pattern : "Elbow Flexion" → "isolation_arm"
- pattern : "vertical_pull" → "isolation"

### Dumbbell Biceps Curl — 8700b73b-11eb-47fb-b270-5014c7893c45

- secondary_muscles : null → []
- muscle_specific : "Biceps brachial" → "Biceps"
- movement_pattern : "Elbow Flexion" → "isolation_arm"
- pattern : "vertical_pull" → "isolation"

### Rear Delt Fly — 8f7fd7f9-aa3b-4231-a33b-492315b7b699

- secondary_muscles : null → []
- movement_pattern : "Horizontal Pull" → "pull_horizontal"
- pattern : "isolation" → "pull"

### Cable Fly / Pec Dec — 908921e6-83fe-4baf-87f3-361a678c47db

- secondary_muscles : null → []
- movement_pattern : "Horizontal Push" → "push_horizontal"
- equipment : null → ["Câble"]
- pattern : "isolation" → "push"

### Standing Calf Raise — 90ec748d-710f-4e0f-951f-ee87581e2219

- secondary_muscles : null → []
- movement_pattern : "Isolation" → "isolation_leg"

### Medicine Ball Chest Pass — 935673ee-71f3-4a2d-8766-feae5969c9af

- secondary_muscles : null → []
- category : null → "push"
- movement_pattern : "Plyometric" → "push_horizontal"
- pattern : null → "push"

### Medicine Ball Slam — 93cc7342-2ded-4c95-bd91-0d47c46efe23

- secondary_muscles : null → []
- category : null → "pull"
- movement_pattern : "Plyometric" → "pull_vertical"
- pattern : null → "pull"

### Broad Jump — 941bd354-bb6a-421e-b86f-01d4176259c6

- category : null → "legs"
- movement_pattern : "Plyometric" → "squat"
- equipment : null → ["Poids du corps"]
- muscle_group : "Jambes" → "Quadriceps"
- pattern : null → "squat"

### Prone Y-T-W Raises — 9501a76d-211f-4a83-9918-7aa8583075a8

- weight_type : "hypertrophy" → "dumbbell"
- category : "back" → "pull"
- movement_pattern : "pull_horizontal" → "isolation_shoulder"
- equipment : ["incline_bench", "light_dumbbells"] → ["incline_bench", "Haltères"]
- muscle_group : "Dos" → "Trapèzes"
- pattern : "pull_horizontal" → "isolation"

### Rack Pull — 97acf66d-e86f-4a02-a262-b6ac19dd88be

- category : "" → "pull"
- movement_pattern : "Hip Hinge" → "hinge"
- pattern : "isolation" → "hinge"

### Rope Hammer Curl — 9877faf0-f077-4de7-9d57-ddc851583396

- movement_pattern : "pull_vertical" → "isolation_arm"
- muscle_group : "Biceps+Avant-bras" → "Avant-bras"
- pattern : "pull" → "isolation"

### Barbell Row — 98c0a477-4482-4184-bb99-bde8a77528f7

- movement_pattern : "Horizontal Pull" → "pull_horizontal"
- pattern : "horizontal_pull" → "pull"

### Push-Up — 98e56d15-a23f-4b74-bd6f-5bb1fc97a73f

- secondary_muscles : null → []
- movement_pattern : "Horizontal Push" → "push_horizontal"
- equipment : null → ["Poids du corps"]
- pattern : "horizontal_push" → "push"

### Bulgarian Split Squat — 992c71f7-aec4-4265-9350-e5e76dcc01b0

- movement_pattern : "Lunge" → "unilateral_leg"
- pattern : "squat" → "lunge"

### Barbell Bent Over Row — 9b496761-0cb5-4960-a82b-857968faef37

- movement_pattern : "Horizontal Pull" → "pull_horizontal"
- pattern : "horizontal_pull" → "pull"

### Barbell Sumo Deadlift — 9b9e0927-c2f8-4596-af3e-9e10e4d984be

- secondary_muscles : null → ["Quadriceps", "Ischio-jambiers"]
- movement_pattern : "Hip Hinge" → "hinge"

### Flat DB Press — 9c04bf68-bdeb-44cb-92ff-eff643fb02d3

- secondary_muscles : null → ["Triceps", "Deltoïde antérieur"]
- movement_pattern : "Horizontal Push" → "push_horizontal"
- pattern : "horizontal_push" → "push"

### Chin-Up — 9f0b0ed9-b7b0-45fa-8225-6cbd03915c3f

- secondary_muscles : null → ["Biceps"]
- movement_pattern : "Vertical Pull" → "pull_vertical"
- equipment : ["Machine"] → ["Poids du corps"]
- pattern : "vertical_pull" → "pull"

### Neck Extension — a4abed3a-9b0d-4ad8-a926-185aa9d81f1c

- secondary_muscles : ["longissimus capitis", "semispinalis capitis", "Trapèze supérieur"] → []
- movement_pattern : "push_vertical" → "other"

### Wall Slides — a5f88a16-9d45-4ac7-8793-51b294c65648

- secondary_muscles : null → []
- category : null → "mobility"
- movement_pattern : "Gainage" → "isolation_shoulder"
- equipment : null → []
- muscle_group : "Épaules" → "Trapèzes"
- pattern : null → "mobility"

### DB Bench Press — a6bcf831-7615-4cdc-b675-c18f871db05e

- secondary_muscles : null → ["Triceps", "Deltoïde antérieur"]
- movement_pattern : "Horizontal Push" → "push_horizontal"
- pattern : "horizontal_push" → "push"

### Barbell Incline Bench Press — ab4b06c0-a64f-4653-8d1a-86085afbfd6e

- secondary_muscles : null → ["Triceps", "Deltoïde antérieur"]
- movement_pattern : "Horizontal Push" → "push_horizontal"
- pattern : "horizontal_push" → "push"

### Pause Bench Press — adf08e12-6859-4f16-afa2-fe6d54e59971

- secondary_muscles : null → ["Triceps", "Deltoïde antérieur"]
- movement_pattern : "Horizontal Push" → "push_horizontal"
- pattern : "horizontal_push" → "push"

### Barbell Romanian Deadlift — b2457e20-6988-412e-9c80-21044a31b973

- muscle_specific : "Biceps fémoral" → "Ischio-jambiers"
- movement_pattern : "Hip Hinge" → "hinge"
- pattern : "pull" → "hinge"

### Plank — b28c8331-7839-404d-817e-3c1b7b2d784c

- secondary_muscles : null → []
- movement_pattern : "Gainage" → "core"
- equipment : null → ["Poids du corps"]
- pattern : "" → "core"

### Barbell Lying Triceps Extension Skull Crusher — b490e7c5-86b9-4ce6-82b6-3917f8fc9e71

- secondary_muscles : null → []
- muscle_specific : "Triceps brachial" → "Triceps"
- movement_pattern : "Elbow Extension" → "isolation_arm"
- pattern : "horizontal_push" → "isolation"

### Cable Y Raise — b86e3362-8734-4bdc-a432-779b21906dd4

- secondary_muscles : null → []
- movement_pattern : "Isolation" → "isolation_shoulder"
- pattern : "vertical_push" → "isolation"

### Single Arm DB Overhead Press — b921a222-5892-4464-98a1-583bfa7d343a

- movement_pattern : "Vertical Push" → "push_vertical"
- pattern : "vertical_push" → "push"

### Reverse curls — b953ce24-0fe9-4180-ba98-919e90f99597

- secondary_muscles : null → []
- movement_pattern : "Elbow Flexion" → "isolation_arm"
- pattern : "vertical_pull" → "isolation"

### Dumbbell Shrug — ba63c8aa-900e-4d7b-be75-81f6dad7895e

- secondary_muscles : null → []
- movement_pattern : "Isolation" → "isolation_shoulder"
- pattern : "horizontal_pull" → "isolation"

### Tibialis Raises — bbbcbcb3-6693-4111-9528-06b8f0d725d9

- weight_type : "endurance" → "bodyweight"
- movement_pattern : "isolation" → "isolation_leg"
- muscle_group : "legs" → "Mollets"

### Hanging Leg Raise — bc9e81bf-119d-4c3f-a339-ae16c6d59526

- movement_pattern : "Gainage" → "core"
- equipment : null → ["Poids du corps"]

### Hack Squat — bda0a383-f3fa-4d71-aae4-1be678dd4084

- movement_pattern : "Squat" → "squat"

### Dumbbell Wrist Curl — c74f4ad6-0243-4293-ad71-8cbef34a75cf

- secondary_muscles : null → []
- movement_pattern : "Isolation" → "accessory_wrist"
- pattern : "vertical_push" → "isolation"

### Cable Woodchopper — c7bbf0fa-3c18-4154-bc80-f6cf9337c136

- secondary_muscles : ["Abdominaux"] → []
- movement_pattern : "Rotation" → "rotation"

### Cossack Squat — c96cc070-d44c-44e4-9658-d40370ebf8e2

- weight_type : "mobility" → "bodyweight"
- movement_pattern : "lunge" → "unilateral_leg"
- equipment : [] → ["Poids du corps"]

### Single-Arm DB Row — cb6ba509-253a-44f7-ae93-3fc4578e2a55

- movement_pattern : "Horizontal Pull" → "pull_horizontal"
- pattern : "horizontal_pull" → "pull"

### Dumbbell Arnold Press — cd09e6d0-9b9a-4ab0-9b1d-4c4a9ba2684b

- movement_pattern : "Vertical Push" → "push_vertical"
- pattern : "isolation" → "push"

### 90/90 Hip + Band Shoulder Rotation — cdac5271-1a7a-4239-972a-fb6ebec1806c

- category : "strength" → "mobility"
- movement_pattern : "Rotation" → "rotation"

### Barbell Upright Row — cdf7b96a-722a-4267-ba32-a4dd816a4607

- category : "pull" → "push"
- movement_pattern : "Vertical Pull" → "pull_vertical"

### Seated Leg Curl — cf4a7ad6-b59a-4fe9-80e3-72f62b94794f

- muscle_specific : "Biceps fémoral" → "Ischio-jambiers"
- movement_pattern : "Isolation" → "isolation_leg"
- pattern : "hinge" → "isolation"

### Seated Z Press — d07b4c3a-07c1-46e4-a607-469f0f512e0e

- movement_pattern : "Vertical Push" → "push_vertical"
- pattern : "vertical_push" → "push"

### Band Shoulder CARs — d12573b8-e2f2-4667-be68-ff8a5bbbfb91

- secondary_muscles : null → []
- category : null → "mobility"
- movement_pattern : "Rotation" → "rotation"
- equipment : null → []
- pattern : null → "mobility"

### Dumbbell Concentration Curl — d2544c9f-2565-46f1-b344-adcc96b96484

- secondary_muscles : null → []
- muscle_specific : "Biceps brachial" → "Biceps"
- movement_pattern : "Elbow Flexion" → "isolation_arm"
- pattern : "vertical_pull" → "isolation"

### Russian Twist — d3d248fd-46b4-4f3b-bf92-bf6c329858cb

- secondary_muscles : null → []
- movement_pattern : "Rotation" → "rotation"
- equipment : null → ["Poids du corps"]

### Weighted Dips — d48ad620-1794-414d-ac93-a86e49085413

- weight_type : "strength" → "bodyweight"
- pattern : "push_horizontal" → "push"

### Cable Pull Over — d9b1359f-d412-4f59-8644-f22ecf3d82cd

- secondary_muscles : null → []
- movement_pattern : "Vertical Pull" → "pull_vertical"
- pattern : "vertical_pull" → "pull"

### Face Pull — ddc39015-32cd-43e9-891b-dc89f5c82e63

- category : "" → "pull"
- movement_pattern : "Horizontal Pull" → "pull_horizontal"
- pattern : "isolation" → "pull"

### Dumbbell Lateral Raise — de2c9e87-0a00-4d54-bc23-a4805413bcd3

- secondary_muscles : null → []
- movement_pattern : "Isolation" → "isolation_shoulder"

### World's Greatest Stretch — e13acf43-f687-4a63-93e9-0b6ab7ca9400

- category : "strength" → "mobility"
- movement_pattern : "Gainage" → "rotation"
- equipment : null → []
- pattern : "isolation" → "mobility"

### Barbell Decline Bench Press — e2f5fab1-1382-49cd-bd1e-7007610f6af9

- secondary_muscles : null → ["Triceps", "Deltoïde antérieur"]
- movement_pattern : "Horizontal Push" → "push_horizontal"
- pattern : "horizontal_push" → "push"

### Leg Press — e5548034-a819-4579-8230-a933a7482e80

- movement_pattern : "Squat" → "squat"

### Pull-Up — e559c4a9-f67f-433e-83dd-8b8b4c916eeb

- secondary_muscles : null → ["Biceps"]
- movement_pattern : "Vertical Pull" → "pull_vertical"
- equipment : null → ["Poids du corps"]
- pattern : "vertical_pull" → "pull"

### Farmer's Carry — eae74946-256e-4f20-bd65-70274dc039c4

- secondary_muscles : null → []
- category : "core" → "pull"
- movement_pattern : "Carry" → "carry"

### Barbell Good Morning — eb20250a-5db1-4acf-8fc8-da5b7314f896

- muscle_specific : "Biceps fémoral" → "Ischio-jambiers"
- movement_pattern : "Hip Hinge" → "hinge"

### Deadhang — f435bd2e-1d48-4543-8c14-1112689a766e

- movement_pattern : "Gainage" → "other"
- equipment : [] → ["Poids du corps"]

### Barbell Lunge — f61760fc-5c55-44f9-a653-ac46f0f6a093

- movement_pattern : "Lunge" → "unilateral_leg"
- pattern : "hinge" → "lunge"

### Walking Lunges — f7e5bdbf-3ce6-4ef2-b31b-966b516e1905

- movement_pattern : "Lunge" → "unilateral_leg"
- pattern : "squat" → "lunge"

### Dumbbell Rear Delt Flys — f82f7b09-970c-4f6d-b638-e3c0478aaba0

- secondary_muscles : null → []
- movement_pattern : "Horizontal Pull" → "pull_horizontal"
- pattern : "horizontal_pull" → "pull"

### Cable Crossover — fa5bd0b0-9217-4c48-9d4f-b131d1908b0b

- secondary_muscles : null → []
- category : null → "push"
- movement_pattern : "Horizontal Push" → "push_horizontal"
- equipment : null → ["Câble"]
- pattern : null → "push"

### Triceps Pushdown — fc506d23-f991-490a-8e46-37dc38461943

- muscle_specific : "Triceps brachial" → "Triceps"
- category : "" → "push"
- movement_pattern : "Elbow Extension" → "isolation_arm"

## Différé — pas déployé ni appliqué

65 lignes, dont 46 actives, ont encore un delta local (le reste concerne les archivées). Voir pending.json pour chaque champ avant/après. La projection after.json + pending.json est exactement candidate.json, vérifiée par test.

La migration future exige d’abord le backend/client compatible, puis une nouvelle relecture et des compare-and-set contre la DB courante. pending.json n’est pas une autorisation de déploiement et aucune écriture différée n’a été exécutée.

## VALIDATION

- 182 tests Python ciblés verts (qualité, taxonomie, parité Swift, volume, adapter, DNA, routes inventaire, Landmine, cockpit Stats et ses repères de volume).
- 35 tests iOS verts : MuscleMapperTests + TrainingDoctrineTests, dont les cibles sans zone et la séparation des détails.
- Build iPhone incrémental final : BUILD SUCCEEDED. Pas de full suite.
- Relecture DB après écritures : égalité de toutes les colonnes sélectionnées avec le plan exact. Index et IDs identiques. Compare-and-set des anciennes valeurs ; aucune écriture via save_exercise/upsert pouvant propager une prescription.
- Aucun changement de default_scheme, tracking_type, type, bar_weight, increment, rest_seconds, load_profile, noms, aliases de recherche, legacy muscles ou deleted_at dans la DB.
- Logs de validation : /tmp/trainingos-catalogue-pass2/ ; git diff --check réussi (exit 0), index vide ; état final consigné dans git-final.txt. master est derrière origin/master de 8 commits, aucune intégration effectuée.

## GIT

Aucun stage, commit, push ou déploiement. Les changements préexistants SmartAlarm, projet Xcode, Programme et tests associés sont conservés. Les écritures DB autorisées sont uniquement celles du plan de cette passe.
