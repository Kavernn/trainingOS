import Foundation

struct WeeklyRecoveryAvg: Codable {
    let weekStart: String
    let avg: Double?

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
        case avg
    }
}

struct SorenessFatigueData: Codable {
    let hasData: Bool
    let weeklySoreness: [WeeklyRecoveryAvg]
    let weeklyFatigue: [WeeklyRecoveryAvg]
    let overreachingWeeks: Int
    let sorenessTrend: String
    let fatigueTrend: String
    let currentSoreness: Double?
    let currentFatigue: Double?
    let message: String

    enum CodingKeys: String, CodingKey {
        case hasData           = "has_data"
        case weeklySoreness    = "weekly_soreness"
        case weeklyFatigue     = "weekly_fatigue"
        case overreachingWeeks = "overreaching_weeks"
        case sorenessTrend     = "soreness_trend"
        case fatigueTrend      = "fatigue_trend"
        case currentSoreness   = "current_soreness"
        case currentFatigue    = "current_fatigue"
        case message
    }
}
