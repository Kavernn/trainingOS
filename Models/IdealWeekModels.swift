import Foundation

struct WeekProfile: Codable {
    let start: String
    let end: String
    let score: Double
    let trainingDays: Int
    let avgRpe: Double
    let avgSleep: Double?
    let goodSleep: Int
    let nutritionDays: Int
    let avgPss: Double?

    enum CodingKeys: String, CodingKey {
        case start, end, score
        case trainingDays  = "training_days"
        case avgRpe        = "avg_rpe"
        case avgSleep      = "avg_sleep"
        case goodSleep     = "good_sleep"
        case nutritionDays = "nutrition_days"
        case avgPss        = "avg_pss"
    }
}

struct WeekGap: Codable {
    let key: String
    let label: String
    let icon: String
    let current: Double
    let ideal: Double
}

struct IdealWeekData: Codable {
    let hasData: Bool
    let bestWeek: WeekProfile?
    let currentWeek: WeekProfile?
    let matchPct: Int?
    let gaps: [WeekGap]
    let totalWeeks: Int

    enum CodingKeys: String, CodingKey {
        case hasData     = "has_data"
        case bestWeek    = "best_week"
        case currentWeek = "current_week"
        case matchPct    = "match_pct"
        case gaps
        case totalWeeks  = "total_weeks"
    }
}
