import Foundation

struct WeeklyCount: Codable {
    let weekStart: String
    let count: Int
}

struct ConsistencyData: Codable {
    let hasData: Bool
    let score: Int?
    let stdDev: Double?
    let avgSessionsPerWeek: Double?
    let trend: String
    let weeklyCounts: [WeeklyCount]
    let message: String

    var scoreColor: String {
        guard let s = score else { return "8E8E93" }
        if s >= 80 { return "34C759" }
        if s >= 60 { return "FF9500" }
        return "FF6B6B"
    }

    var trendIcon: String {
        switch trend {
        case "improving": return "arrow.up.right"
        case "declining": return "arrow.down.right"
        default:          return "arrow.right"
        }
    }

    var trendColor: String {
        switch trend {
        case "improving": return "34C759"
        case "declining": return "FF6B6B"
        default:          return "FF9500"
        }
    }
}
