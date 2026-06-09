import Foundation

struct CompoundScore: Codable {
    let score: Double
    let baseConsistency: Double
    let currentStreak: Int
    let multiplier: Double
    let deltaVs30d: Double
    let trend: String
    let hasBaseline: Bool
    let breakdown: CompoundBreakdown

    enum CodingKeys: String, CodingKey {
        case score, trend, multiplier, breakdown
        case baseConsistency = "base_consistency"
        case currentStreak   = "current_streak"
        case deltaVs30d      = "delta_vs_30d"
        case hasBaseline     = "has_baseline"
    }

    init(from decoder: Decoder) throws {
        let c           = try decoder.container(keyedBy: CodingKeys.self)
        score           = (try? c.decodeIfPresent(Double.self,          forKey: .score))           ?? 0.0
        baseConsistency = (try? c.decodeIfPresent(Double.self,          forKey: .baseConsistency)) ?? 0.0
        currentStreak   = (try? c.decodeIfPresent(Int.self,             forKey: .currentStreak))   ?? 0
        multiplier      = (try? c.decodeIfPresent(Double.self,          forKey: .multiplier))      ?? 1.0
        deltaVs30d      = (try? c.decodeIfPresent(Double.self,          forKey: .deltaVs30d))      ?? 0.0
        trend           = (try? c.decodeIfPresent(String.self,          forKey: .trend))           ?? "stable"
        hasBaseline     = (try? c.decodeIfPresent(Bool.self,            forKey: .hasBaseline))     ?? false
        breakdown       = (try? c.decodeIfPresent(CompoundBreakdown.self, forKey: .breakdown))     ?? .empty
    }

    var trendLabel: String {
        switch trend {
        case "hausse": return "En hausse"
        case "baisse": return "En baisse"
        default:       return "Stable"
        }
    }

    var isAboveBaseline: Bool { score > 100 }

    var formattedScore: String { String(format: "%.0f", score) }

    var formattedDelta: String {
        let sign = deltaVs30d >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", deltaVs30d)) pts"
    }
}

struct CompoundBreakdown: Codable {
    let workoutDays: Int
    let nutritionDays: Int
    let activeDays: Int
    let totalDays: Int

    static let empty = CompoundBreakdown(workoutDays: 0, nutritionDays: 0, activeDays: 0, totalDays: 30)

    enum CodingKeys: String, CodingKey {
        case workoutDays   = "workout_days"
        case nutritionDays = "nutrition_days"
        case activeDays    = "active_days"
        case totalDays     = "total_days"
    }
}
