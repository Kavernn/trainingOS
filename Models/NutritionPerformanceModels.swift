import Foundation

struct NutritionPerformanceData: Codable {
    let hasData: Bool
    let avgRpeWith: Double?
    let avgRpeWithout: Double?
    let countWith: Int
    let countWithout: Int
    let rpeDiff: Double?
    let impactPct: Int?
    let sessionsAnalyzed: Int
    let message: String

    var impactDirection: ImpactDirection {
        guard let diff = rpeDiff else { return .neutral }
        if diff >= 0.5 { return .positive }
        if diff <= -0.5 { return .negative }
        return .neutral
    }

    var formattedRpeDiff: String {
        guard let diff = rpeDiff else { return "—" }
        let sign = diff >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", diff))"
    }

    enum ImpactDirection {
        case positive, negative, neutral
        var colorHex: String {
            switch self {
            case .positive: return "34C759"
            case .negative: return "FF9500"
            case .neutral:  return "8E8E93"
            }
        }
        var icon: String {
            switch self {
            case .positive: return "arrow.up.circle.fill"
            case .negative: return "arrow.down.circle.fill"
            case .neutral:  return "equal.circle.fill"
            }
        }
        var label: String {
            switch self {
            case .positive: return "Impact positif"
            case .negative: return "Impact négatif"
            case .neutral:  return "Impact neutre"
            }
        }
    }
}
