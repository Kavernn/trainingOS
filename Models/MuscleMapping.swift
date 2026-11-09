import Foundation

enum MuscleZone: String, CaseIterable, Hashable {
    case chest
    case shoulders
    case biceps
    case core
    case quads
    case generalBack
    case traps
    case triceps
    case glutes
    case hamstrings
    case calves
}

struct MuscleZoneScore: Equatable {
    let zone: MuscleZone
    let score: Int
}

struct MuscleMappingResult: Equatable {
    let scoresByZone: [MuscleZone: Int]
    var unmappedMuscles: [String] = []

    var zones: Set<MuscleZone> {
        Set(scoresByZone.compactMap { zone, score in score > 0 ? zone : nil })
    }

    func rankedZones(limit: Int? = nil) -> [MuscleZoneScore] {
        let ranked = scoresByZone
            .filter { $0.value > 0 }
            .map { MuscleZoneScore(zone: $0.key, score: $0.value) }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.zone.rawValue < $1.zone.rawValue
            }

        guard let limit = limit else { return ranked }
        return Array(ranked.prefix(max(0, limit)))
    }
}

enum MuscleMapper {
    static func map(_ metadata: ExerciseMuscleMetadata) -> MuscleMappingResult {
        var scores: [MuscleZone: Int] = [:]

        let primary = zone(for: metadata.muscleSpecific) ?? zone(for: metadata.muscleGroup)
        if let primary = primary {
            scores[primary, default: 0] += 2
        }

        let secondaryZones = Set(metadata.secondaryMuscles.compactMap { zone(for: $0) })
        for secondary in secondaryZones where secondary != primary {
            scores[secondary, default: 0] += 1
        }

        let hasExplicitZone = primary != nil || !secondaryZones.isEmpty
        if !hasExplicitZone {
            let legacyZones = Set(metadata.legacyMuscles.compactMap { zone(for: $0) })
            for legacy in legacyZones {
                scores[legacy, default: 0] += 1
            }
        }

        let targets = [metadata.muscleSpecific ?? metadata.muscleGroup].compactMap { $0 } + metadata.secondaryMuscles
        let unmapped = Array(Set(targets.filter { zone(for: $0) == nil }.map(CatalogueTaxonomy.muscle))).sorted()
        return MuscleMappingResult(scoresByZone: scores, unmappedMuscles: unmapped)
    }

    static func aggregate(_ metadata: [ExerciseMuscleMetadata]) -> MuscleMappingResult {
        var scores: [MuscleZone: Int] = [:]

        var unmapped = Set<String>()
        for exercise in metadata {
            let result = map(exercise)
            unmapped.formUnion(result.unmappedMuscles)
            for (zone, score) in result.scoresByZone {
                scores[zone, default: 0] += score
            }
        }

        return MuscleMappingResult(scoresByZone: scores, unmappedMuscles: unmapped.sorted())
    }

    static func zone(for rawValue: String?) -> MuscleZone? {
        guard let rawValue = rawValue else { return nil }
        return zoneByNormalizedLabel[normalizedKey(rawValue)] ?? zoneByNormalizedLabel[normalizedKey(CatalogueTaxonomy.muscle(rawValue))]
    }

    private static func normalizedKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "fr_CA")
            )
            .lowercased(with: Locale(identifier: "fr_CA"))
    }

    private static let labelsByZone: [MuscleZone: [String]] = [
        .chest: [
            "chest", "pectoraux", "pectoraux supérieurs", "pectorals", "pectoral", "pecs",
            "upper chest", "lower chest", "lower_chest", "pectoral majeur",
            "pectoral majeur — chef claviculaire", "pectoral majeur — chef sternal",
            "pectoral majeur — chef costal", "chef claviculaire", "chef sternal inférieur",
            "pectoral mineur"
        ],
        .shoulders: [
            "épaules", "épaules post.", "shoulder", "shoulders", "deltoïde", "deltoïdes",
            "deltoid", "deltoids", "delt", "delts", "deltoïdes antérieurs",
            "deltoïdes latéraux", "deltoïdes postérieurs", "deltoïde antérieur",
            "deltoïde médial", "deltoïde latéral", "deltoïde postérieur",
            "anterior deltoid", "lateral deltoid", "posterior deltoid", "rear deltoid",
            "rear delts", "front_delts", "rear_delts"
        ],
        .biceps: [
            "biceps", "biceps_short", "biceps brachial", "biceps brachial — longue portion",
            "biceps brachial — courte portion", "brachial", "brachialis"
        ],
        .core: [
            "core", "abdominaux", "abdominals", "abdominaux obliques", "abs", "gainage",
            "obliques", "rectus abdominis", "droit de l'abdomen", "droit de l’abdomen",
            "oblique externe", "oblique interne", "transverse", "transverse de l'abdomen",
            "transverse de l’abdomen", "carré des lombes"
        ],
        .quads: [
            "quadriceps", "quads", "quad", "vaste latéral", "vaste médial",
            "vaste intermédiaire", "droit fémoral"
        ],
        .generalBack: [
            "dos", "back", "lats", "grand dorsal", "upper back", "lower back", "haut du dos",
            "bas du dos", "rhomboïdes", "rhomboids", "grand rond", "teres_major",
            "érecteurs du rachis", "multifides"
        ],
        .traps: [
            "trapèzes", "traps", "trap", "trapezius", "trapèze supérieur",
            "trapèze moyen",
            "trapèze — chef supérieur", "trapèze — chef moyen", "trapèze — chef inférieur",
            "mid_traps"
        ],
        .triceps: [
            "triceps", "triceps brachial", "chef long du triceps", "triceps_long",
            "triceps_lateral", "triceps_medial", "triceps — longue portion",
            "triceps — chef latéral", "triceps — chef médial"
        ],
        .glutes: [
            "fessiers", "fessier", "glutes", "glute", "gluteus", "gluteus maximus",
            "gluteus medius", "grand fessier", "moyen fessier", "petit fessier"
        ],
        .hamstrings: [
            "ischio-jambiers", "ischiojambiers", "hamstrings", "hams", "ham",
            "biceps fémoral — longue portion", "biceps fémoral — courte portion",
            "semi-tendineux", "semi-membraneux"
        ],
        .calves: [
            "mollets", "mollet", "calves", "calf", "soleus", "soléaire", "gastrocnémien",
            "gastrocnémien — chef médial", "gastrocnémien — chef latéral"
        ]
    ]

    private static let zoneByNormalizedLabel: [String: MuscleZone] = {
        var result: [String: MuscleZone] = [:]
        for (zone, labels) in labelsByZone {
            for label in labels {
                result[normalizedKey(label)] = zone
            }
        }
        return result
    }()
}

// BEGIN GENERATED CATALOGUE TAXONOMY — scripts/generate_catalogue_taxonomy_swift.py
// Broad reporting groups and detailed targets are separate concepts.
enum CatalogueTaxonomy {
    static let musclesByGroup: [(group: String, specifics: [String])] = [
("Pectoraux", ["Pectoral majeur", "Pectoral supérieur", "Pectoral moyen", "Pectoral inférieur", "Pectoral mineur", "Serratus antérieur", "Pectoraux"]),
("Dos", ["Haut du dos", "Grand dorsal", "Rhomboïdes", "Grand rond", "Érecteurs du rachis", "Multifides", "Dos"]),
("Épaules", ["Deltoïdes", "Coiffe des rotateurs", "Deltoïde antérieur", "Deltoïde médial", "Deltoïde postérieur", "Sous-épineux", "Supra-épineux", "Sous-scapulaire", "Petit rond", "Épaules"]),
("Triceps", ["Triceps — longue portion", "Triceps — chef latéral", "Triceps — chef médial", "Anconé", "Triceps"]),
("Quadriceps", ["Quadriceps", "Vaste latéral", "Vaste médial", "Vaste intermédiaire", "Droit fémoral"]),
("Ischio-jambiers", ["Ischio-jambiers", "Biceps fémoral", "Biceps fémoral — longue portion", "Biceps fémoral — courte portion", "Semi-tendineux", "Semi-membraneux"]),
("Fessiers", ["Grand fessier", "Moyen fessier", "Petit fessier", "Tenseur du fascia lata", "Fessiers"]),
("Mollets", ["Gastrocnémien", "Gastrocnémien — chef médial", "Gastrocnémien — chef latéral", "Soléaire", "Tibial antérieur", "Mollets"]),
("Core", ["Obliques", "Plancher pelvien", "Droit abdominal", "Oblique externe", "Oblique interne", "Transverse de l'abdomen", "Carré des lombes", "Psoas"]),
("Hanches", ["Adducteurs", "Fléchisseurs de hanche", "Grand adducteur", "Long adducteur", "Court adducteur", "Gracile", "Pectiné"]),
("Cou", ["Sterno-cléido-mastoïdien", "Splénius", "Cou"]),
("Autre", []),
("Biceps", ["Brachial", "Biceps brachial — longue portion", "Biceps brachial — courte portion", "Biceps"]),
("Avant-bras", ["Brachioradialis", "Supinateur", "Fléchisseurs du poignet", "Extenseurs du poignet", "Fléchisseurs des doigts", "Avant-bras"]),
("Trapèzes", ["Trapèze supérieur", "Trapèze moyen", "Trapèze inférieur", "Trapèzes"])]
    static let movementPatterns: [(String, String)] = [
("push_horizontal", "Poussée horizontale"),
("push_vertical", "Poussée verticale"),
("pull_horizontal", "Tirage horizontal"),
("pull_vertical", "Tirage vertical"),
("squat", "Squat / Quad"),
("hinge", "Charnière / Hanche"),
("unilateral_leg", "Unilatéral jambe"),
("press_machine", "Presse machine"),
("isolation_arm", "Isolation bras"),
("isolation_shoulder", "Isolation épaule"),
("isolation_leg", "Isolation jambe"),
("core", "Core / Gainage"),
("rotation", "Rotation"),
("carry", "Carry / Transport"),
("cardio", "Cardio"),
("accessory_wrist", "Accessoire poignet"),
("other", "Autre")]
    static let equipmentOptions: [String] = ["Barre", "Haltères", "Machine", "Câble", "Bandes", "Poids du corps", "Smith Machine", "TRX", "Autre", "bench", "incline_bench", "neck harness", "plate", "medicine ball", "handle", "box", "bike", "rower", "nordic_bench", "partner", "ez_bar", "wall", "dip_bars", "weight_belt"]
    static let muscleAliases: [String: String] = ["Pectoral majeur — chef claviculaire": "Pectoral supérieur",
"Pectoral majeur — chef sternal": "Pectoral moyen",
"Pectoral majeur — chef costal": "Pectoral inférieur",
"Droit de l'abdomen": "Droit abdominal",
"Droit de l’abdomen": "Droit abdominal",
"Brachialis": "Brachial",
"Trapèze — chef supérieur": "Trapèze supérieur",
"Trapèze — chef moyen": "Trapèze moyen",
"Trapèze — chef inférieur": "Trapèze inférieur",
"Hip Flexors": "Fléchisseurs de hanche",
"hip flexors": "Fléchisseurs de hanche",
"hip_flexors": "Fléchisseurs de hanche",
"adductors": "Adducteurs",
"tibialis_anterior": "Tibial antérieur",
"rectus_abdominis": "Droit abdominal",
"rectus abdominis": "Droit abdominal",
"Abdominaux": "Droit abdominal",
"chest": "Pectoraux",
"pectorals": "Pectoraux",
"pecs": "Pectoraux",
"upper chest": "Pectoral supérieur",
"lower chest": "Pectoral inférieur",
"lower_chest": "Pectoral inférieur",
"back": "Dos",
"lats": "Grand dorsal",
"upper back": "Haut du dos",
"rhomboids": "Rhomboïdes",
"lower back": "Érecteurs du rachis",
"traps": "Trapèzes",
"trapezius": "Trapèzes",
"mid_traps": "Trapèze moyen",
"shoulders": "Épaules",
"deltoids": "Deltoïdes",
"delts": "Deltoïdes",
"front_delts": "Deltoïde antérieur",
"anterior deltoid": "Deltoïde antérieur",
"lateral deltoid": "Deltoïde médial",
"rear delts": "Deltoïde postérieur",
"rear_delts": "Deltoïde postérieur",
"rear deltoid": "Deltoïde postérieur",
"posterior deltoid": "Deltoïde postérieur",
"rotator_cuff": "Coiffe des rotateurs",
"triceps_long": "Triceps — longue portion",
"triceps_lateral": "Triceps — chef latéral",
"triceps_medial": "Triceps — chef médial",
"forearms": "Avant-bras",
"quads": "Quadriceps",
"hamstrings": "Ischio-jambiers",
"glutes": "Fessiers",
"gluteus maximus": "Grand fessier",
"gluteus medius": "Moyen fessier",
"calves": "Mollets",
"soleus": "Soléaire",
"abs": "Droit abdominal",
"neck": "Cou",
"pelvic floor": "Plancher pelvien",
"Biceps brachial": "Biceps",
"Triceps brachial": "Triceps"]
    static let groupAliases: [String: String] = ["Abdominaux": "Core",
"glutes": "Fessiers",
"Biceps+Avant-bras": "Biceps",
"Gainage": "Core"]
    static let patternAliases: [String: String] = ["Horizontal Push": "push_horizontal",
"horizontal_push": "push_horizontal",
"Horizontal Pull": "pull_horizontal",
"horizontal_pull": "pull_horizontal",
"Vertical Push": "push_vertical",
"vertical_push": "push_vertical",
"Vertical Pull": "pull_vertical",
"vertical_pull": "pull_vertical",
"Hip Hinge": "hinge",
"Hip Extension": "hinge",
"Squat": "squat",
"Gainage": "core",
"Rotation": "rotation",
"Carry": "carry",
"Cardio": "cardio",
"Elbow Flexion": "isolation_arm",
"Elbow Extension": "isolation_arm",
"Hip Abduction": "isolation_leg",
"Lunge": "unilateral_leg",
"lunge": "unilateral_leg"]
    static func muscle(_ value: String) -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let canonical = musclesByGroup.flatMap(\.specifics).first(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) { return canonical }
        return muscleAliases.first(where: { $0.key.caseInsensitiveCompare(value) == .orderedSame })?.value ?? value
    }
    static func group(_ value: String) -> String {
        groupAliases[value] ?? value
    }
    static func pattern(_ value: String, group: String) -> String {
        if let canonical = patternAliases[value] { return canonical }
        if value.lowercased() == "isolation" {
            switch group {
            case "Biceps", "Triceps": return "isolation_arm"
            case "Avant-bras": return "accessory_wrist"
            case "Épaules", "Trapèzes": return "isolation_shoulder"
            case "Quadriceps", "Ischio-jambiers", "Fessiers", "Mollets", "Hanches": return "isolation_leg"
            default: break
            }
        }
        return value
    }
}
// END GENERATED CATALOGUE TAXONOMY
