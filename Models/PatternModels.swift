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

struct MacroThreshold: Codable {
    let macro: String   // "proteines" / "glucides" / "calories"
    let value: Double   // seuil en grammes ou kcal
    let unit: String    // "g" ou "kcal"
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
    var isNew: Bool
    var warRoom: Bool
    var trend: PatternTrend?
    let macroThreshold: MacroThreshold?

    enum CodingKeys: String, CodingKey {
        case id, family, headline, confidence, n, icon, color, pinned, trend
        case subLabel        = "sub_label"
        case effectPct       = "effect_pct"
        case barA            = "bar_a"
        case barB            = "bar_b"
        case isNew           = "is_new"
        case warRoom         = "war_room"
        case macroThreshold  = "macro_threshold"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(String.self,      forKey: .id)
        family         = try c.decode(String.self,      forKey: .family)
        subLabel       = try c.decode(String.self,      forKey: .subLabel)
        headline       = try c.decode(String.self,      forKey: .headline)
        confidence     = try c.decode(String.self,      forKey: .confidence)
        effectPct      = try c.decode(Double.self,      forKey: .effectPct)
        n              = try c.decode(Int.self,         forKey: .n)
        barA           = try c.decode(PatternBar.self,  forKey: .barA)
        barB           = try c.decode(PatternBar.self,  forKey: .barB)
        icon           = try c.decode(String.self,      forKey: .icon)
        color          = try c.decode(String.self,      forKey: .color)
        pinned         = try c.decode(Bool.self,        forKey: .pinned)
        isNew          = try c.decode(Bool.self,        forKey: .isNew)
        warRoom        = try c.decodeIfPresent(Bool.self,           forKey: .warRoom) ?? false
        trend          = try c.decodeIfPresent(PatternTrend.self,   forKey: .trend)
        macroThreshold = try c.decodeIfPresent(MacroThreshold.self, forKey: .macroThreshold)
    }
}

struct PatternBar: Codable {
    let label: String
    let value: Double
    let frac: Double        // 0.0–1.0 relative to max bar
}

struct PatternTrend: Codable {
    let direction: String   // "rising" | "falling" | "stable"
    let deltaPct: Double
    let initialPct: Double
    let currentPct: Double

    enum CodingKeys: String, CodingKey {
        case direction
        case deltaPct   = "delta_pct"
        case initialPct = "initial_pct"
        case currentPct = "current_pct"
    }

    var arrow: String {
        switch direction {
        case "rising":  return "↑"
        case "falling": return "↓"
        default:        return "→"
        }
    }

    var isSignificant: Bool { abs(deltaPct) >= 3 }
}
