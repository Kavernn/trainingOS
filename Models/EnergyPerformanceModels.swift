import Foundation

struct EnergyBucket: Codable {
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

struct EnergyPerformanceData: Codable {
    let hasData: Bool
    let buckets: [EnergyBucket]
    let bestEnergy: String?
    let sessionsAnalyzed: Int
    let rpeDiff: Double?
    let message: String

    enum CodingKeys: String, CodingKey {
        case hasData          = "has_data"
        case buckets
        case bestEnergy       = "best_energy"
        case sessionsAnalyzed = "sessions_analyzed"
        case rpeDiff          = "rpe_diff"
        case message
    }
}
