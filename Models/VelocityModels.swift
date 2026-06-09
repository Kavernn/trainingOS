import Foundation

struct VelocityData: Codable {
    let velocity: Double?
    let acceleration: Double?
    let label: String
    let weeklyScores: [Double?]
    let trendPct: Double?
    let hasBaseline: Bool

    enum CodingKeys: String, CodingKey {
        case velocity, acceleration, label
        case weeklyScores = "weekly_scores"
        case trendPct     = "trend_pct"
        case hasBaseline  = "has_baseline"
    }

    init(from decoder: Decoder) throws {
        let c        = try decoder.container(keyedBy: CodingKeys.self)
        velocity     = try? c.decodeIfPresent(Double.self, forKey: .velocity)
        acceleration = try? c.decodeIfPresent(Double.self, forKey: .acceleration)
        label        = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? "foundation"
        trendPct     = try? c.decodeIfPresent(Double.self, forKey: .trendPct)
        hasBaseline  = (try? c.decodeIfPresent(Bool.self,  forKey: .hasBaseline)) ?? false

        // weekly_scores is [number | null] in JSON
        if let raw = try? c.decodeIfPresent([Double?].self, forKey: .weeklyScores) {
            weeklyScores = raw
        } else {
            weeklyScores = []
        }
    }

    var velocityLabel: String {
        switch label {
        case "accélération": return "Accélération"
        case "stable":       return "Stable"
        case "décélération": return "Décélération"
        case "chute_libre":  return "Chute libre"
        default:             return "Fondation"
        }
    }

    var isAccelerating: Bool { label == "accélération" }
    var isDecelerating: Bool { label == "décélération" || label == "chute_libre" }

    var formattedVelocity: String {
        guard let v = velocity else { return "—" }
        let sign = v >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", v))%"
    }

    var formattedTrend: String {
        guard let t = trendPct else { return "—" }
        let sign = t >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.0f", t))% / 4 sem."
    }
}
