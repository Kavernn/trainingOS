import Foundation

struct SleepHRVBucket: Codable {
    let bucket: String
    let label: String
    let avgHrv: Double?
    let count: Int

    enum CodingKeys: String, CodingKey {
        case bucket
        case label
        case avgHrv = "avg_hrv"
        case count
    }
}

struct SleepHRVData: Codable {
    let hasData: Bool
    let buckets: [SleepHRVBucket]
    let bestBucket: String?
    let sessionsAnalyzed: Int
    let message: String

    enum CodingKeys: String, CodingKey {
        case hasData           = "has_data"
        case buckets
        case bestBucket        = "best_bucket"
        case sessionsAnalyzed  = "sessions_analyzed"
        case message
    }
}
