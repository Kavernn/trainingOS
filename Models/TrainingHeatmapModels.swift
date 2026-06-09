import Foundation

struct HeatmapWeek: Codable {
    let weekStart: String
    let days: [Int]

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
        case days
    }
}

struct TrainingHeatmapData: Codable {
    let hasData: Bool
    let weeks: [HeatmapWeek]
    let totalByDay: [Int]
    let bestDayIndex: Int?
    let sessionsTracked: Int
    let message: String

    enum CodingKeys: String, CodingKey {
        case hasData         = "has_data"
        case weeks
        case totalByDay      = "total_by_day"
        case bestDayIndex    = "best_day_index"
        case sessionsTracked = "sessions_tracked"
        case message
    }
}
