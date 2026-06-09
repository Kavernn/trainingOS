import Foundation

struct WeeklyWeightAvg: Codable {
    let weekStart: String
    let avg: Double?

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
        case avg
    }
}

struct BodyWeightTrendData: Codable {
    let hasData: Bool
    let weeklyAvgs: [WeeklyWeightAvg]
    let trend: String
    let currentWeight: Double?
    let changePct: Double?
    let currentPctOfRange: Int?
    let rangeHigh: Double?
    let rangeLow: Double?
    let message: String

    enum CodingKeys: String, CodingKey {
        case hasData           = "has_data"
        case weeklyAvgs        = "weekly_avgs"
        case trend
        case currentWeight     = "current_weight"
        case changePct         = "change_pct"
        case currentPctOfRange = "current_pct_of_range"
        case rangeHigh         = "range_high"
        case rangeLow          = "range_low"
        case message
    }
}
