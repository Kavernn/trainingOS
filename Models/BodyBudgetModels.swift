import Foundation

struct BodyBudgetResponse: Codable {
    let score: Int
    let trend: String       // "up" | "down" | "stable"
    let insight: String
    let pillars: BodyBudgetPillars
    let computedAt: String

    enum CodingKeys: String, CodingKey {
        case score, trend, insight, pillars
        case computedAt = "computed_at"
    }
}

struct BodyBudgetPillars: Codable {
    let training: Int
    let stress: Int
    let nutrition: Int
}
