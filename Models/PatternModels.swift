import Foundation

struct PatternResponse: Codable {
    let daily: PatternEntry?
    let pinned: [PatternEntry]
    let total: Int
    let computedAt: String

    enum CodingKeys: String, CodingKey {
        case daily, pinned, total
        case computedAt = "computed_at"
    }
}

struct PatternEntry: Codable, Identifiable {
    let id: String
    let family: String
    let subLabel: String
    let headline: String
    let confidence: String  // "forte" | "modérée"
    let effectPct: Double
    let n: Int
    let barA: PatternBar
    let barB: PatternBar
    let icon: String
    let color: String
    var pinned: Bool

    enum CodingKeys: String, CodingKey {
        case id, family, headline, confidence, n, icon, color, pinned
        case subLabel   = "sub_label"
        case effectPct  = "effect_pct"
        case barA       = "bar_a"
        case barB       = "bar_b"
    }
}

struct PatternBar: Codable {
    let label: String
    let value: Double
    let frac: Double        // 0.0–1.0 relative to max bar
}
