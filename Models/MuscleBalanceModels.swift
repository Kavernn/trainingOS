import Foundation

// MARK: - Muscle Balance (push/pull/legs/core %)

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

// MARK: - Muscle Imbalance (agonist/antagonist pairs)

struct MuscleAntagonistPair: Codable, Identifiable {
    var id: String { key }
    let key: String
    let agonistLabel: String
    let antagonistLabel: String
    let agonistSets: Int
    let antagonistSets: Int
    let ratio: Double?
    let idealRatio: Double
    let status: String          // "balanced" | "imbalanced_high" | "imbalanced_low" | "insufficient_data"
    let message: String
    let source: String

    var isImbalanced: Bool { status.hasPrefix("imbalanced") }

    var statusColor: String {
        switch status {
        case "balanced":          return "green"
        case "imbalanced_high",
             "imbalanced_low":    return "orange"
        default:                  return "gray"
        }
    }

    enum CodingKeys: String, CodingKey {
        case key, ratio, status, message, source
        case agonistLabel     = "agonist_label"
        case antagonistLabel  = "antagonist_label"
        case agonistSets      = "agonist_sets"
        case antagonistSets   = "antagonist_sets"
        case idealRatio       = "ideal_ratio"
    }
}

struct MuscleImbalanceData: Codable {
    let hasData: Bool
    let pairs: [MuscleAntagonistPair]
    let hasImbalance: Bool
    let totalAnalyzed: Int
    let periodDays: Int

    enum CodingKeys: String, CodingKey {
        case pairs
        case hasData       = "has_data"
        case hasImbalance  = "has_imbalance"
        case totalAnalyzed = "total_analyzed"
        case periodDays    = "period_days"
    }
}

// MARK: - Muscle Volume (hard sets + MEV)

struct MuscleHardSetsEntry: Codable, Identifiable {
    var id: String { label }
    let sets: Int
    let status: String    // "low" | "optimal" | "high"
    let label: String
    let recommendation: String
}

struct MuscleVolumeAvgEntry: Codable, Identifiable {
    var id: String { label }
    let avgSetsPerWeek: Double
    let label: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case label, status
        case avgSetsPerWeek = "avg_sets_per_week"
    }
}

struct MuscleNeglectedEntry: Codable, Identifiable {
    var id: String { muscle }
    let muscle: String
    let label: String
    let avgSetsPerWeek: Double
    let mev: Int
    let deficit: Double

    enum CodingKeys: String, CodingKey {
        case muscle, label, mev, deficit
        case avgSetsPerWeek = "avg_sets_per_week"
    }
}

struct MuscleVolumeData: Codable {
    let currentWeek: [String: MuscleHardSetsEntry]
    let weeklyAvg: [String: MuscleVolumeAvgEntry]
    let neglected: [MuscleNeglectedEntry]
    let mev: Int
    let mav: Int
    let trendDays: Int

    enum CodingKeys: String, CodingKey {
        case neglected, mev, mav
        case currentWeek = "current_week"
        case weeklyAvg   = "weekly_avg"
        case trendDays   = "trend_days"
    }
}
