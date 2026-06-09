import Foundation

struct WeeklyQuality: Codable {
    let weekStart: String
    let avgQuality: Double?
    let sessionCount: Int

    enum CodingKeys: String, CodingKey {
        case weekStart     = "week_start"
        case avgQuality    = "avg_quality"
        case sessionCount  = "session_count"
    }
}

struct BestSession: Codable {
    let date: String
    let score: Double
}

struct SessionQualityData: Codable {
    let hasData: Bool
    let weeklyQuality: [WeeklyQuality]
    let trend: String
    let avgQuality: Double?
    let bestSession: BestSession?
    let message: String

    enum CodingKeys: String, CodingKey {
        case hasData       = "has_data"
        case weeklyQuality = "weekly_quality"
        case trend
        case avgQuality    = "avg_quality"
        case bestSession   = "best_session"
        case message
    }
}
