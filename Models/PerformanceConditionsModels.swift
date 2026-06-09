import Foundation

struct PerformanceCondition: Codable {
    let key: String
    let label: String
    let icon: String
    let frequency: Int
    let matchToday: Bool

    enum CodingKeys: String, CodingKey {
        case key, label, icon, frequency
        case matchToday = "match_today"
    }
}

struct PerformanceConditionsData: Codable {
    let hasData: Bool
    let conditions: [PerformanceCondition]
    let alignmentScore: Int?
    let matched: Int
    let total: Int
    let message: String

    enum CodingKeys: String, CodingKey {
        case hasData = "has_data"
        case conditions, matched, total, message
        case alignmentScore = "alignment_score"
    }
}
