import Foundation

struct WeeklyLoad: Codable {
    let weekStart: String
    let load: Double

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
        case load
    }
}

struct VolumeProgressionData: Codable {
    let hasData: Bool
    let weeklyLoads: [WeeklyLoad]
    let trend: String
    let peakLoad: Double?
    let currentPctOfPeak: Int?
    let message: String

    enum CodingKeys: String, CodingKey {
        case hasData           = "has_data"
        case weeklyLoads       = "weekly_loads"
        case trend
        case peakLoad          = "peak_load"
        case currentPctOfPeak  = "current_pct_of_peak"
        case message
    }
}
