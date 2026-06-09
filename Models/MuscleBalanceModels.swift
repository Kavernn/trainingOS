import Foundation

struct MuscleRatios: Codable {
    let push: Int
    let pull: Int
    let legs: Int
    let core: Int
    let cardio: Int
}

struct MuscleImbalance: Codable {
    let key: String
    let label: String
    let icon: String
    let detail: String
}

struct MuscleBalanceData: Codable {
    let hasData: Bool
    let ratios: MuscleRatios?
    let imbalances: [MuscleImbalance]
    let totalAnalyzed: Int
    let topCategory: String?

    var topCategoryLabel: String {
        switch topCategory {
        case "push":   return "Push"
        case "pull":   return "Pull"
        case "legs":   return "Jambes"
        case "core":   return "Core"
        case "cardio": return "Cardio"
        default:       return topCategory?.capitalized ?? "—"
        }
    }

    var topCategoryIcon: String {
        switch topCategory {
        case "push":   return "arrow.up.circle.fill"
        case "pull":   return "arrow.down.circle.fill"
        case "legs":   return "figure.run"
        case "core":   return "tornado"
        case "cardio": return "heart.fill"
        default:       return "dumbbell.fill"
        }
    }
}
