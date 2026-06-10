import Foundation

struct WeeklyDurationAvg: Codable {
    let weekStart: String
    let avgMin: Double?
    let count: Int

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
        case avgMin    = "avg_min"
        case count
    }
}

struct DurationBucket: Codable {
    let bucket: String
    let label: String
    let avgRpe: Double?
    let count: Int

    enum CodingKeys: String, CodingKey {
        case bucket
        case label
        case avgRpe = "avg_rpe"
        case count
    }
}

struct WorkoutDurationData: Codable {
    let hasData: Bool
    let weeklyAvgs: [WeeklyDurationAvg]
    let avgDuration: Double?
    let trend: String
    let byLength: [DurationBucket]
    let sessionsAnalyzed: Int
    let message: String

    enum CodingKeys: String, CodingKey {
        case hasData          = "has_data"
        case weeklyAvgs       = "weekly_avgs"
        case avgDuration      = "avg_duration"
        case trend
        case byLength         = "by_length"
        case sessionsAnalyzed = "sessions_analyzed"
        case message
    }
}
