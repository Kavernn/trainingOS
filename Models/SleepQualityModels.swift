import Foundation

struct WeeklySleepScore: Codable {
    let weekStart: String
    let score: Double?
    let count: Int

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
        case score
        case count
    }
}

struct SleepQualityData: Codable {
    let hasData: Bool
    let weeklyScores: [WeeklySleepScore]
    let trend: String
    let avgScore: Double?
    let currentScore: Double?
    let message: String

    enum CodingKeys: String, CodingKey {
        case hasData      = "has_data"
        case weeklyScores = "weekly_scores"
        case trend
        case avgScore     = "avg_score"
        case currentScore = "current_score"
        case message
    }
}
