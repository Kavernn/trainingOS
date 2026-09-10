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

        return MuscleMappingResult(scoresByZone: scores)
    }

    static func aggregate(_ metadata: [ExerciseMuscleMetadata]) -> MuscleMappingResult {
        var scores: [MuscleZone: Int] = [:]

        for exercise in metadata {
            for (zone, score) in map(exercise).scoresByZone {
                scores[zone, default: 0] += score
            }
        }

        return MuscleMappingResult(scoresByZone: scores)
    }

    static func zone(for rawValue: String?) -> MuscleZone? {
        guard let rawValue = rawValue else { return nil }
        return zoneByNormalizedLabel[normalizedKey(rawValue)]
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
