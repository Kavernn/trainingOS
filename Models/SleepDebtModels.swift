import Foundation

struct SleepDebtData: Codable {
    let hasData: Bool
    let debt7d: Double?
    let debt30d: Double?
    let avgSleep7d: Double?
    let target: Double
    let trend: String
    let nightsToRecover: Int?
    let logged7d: Int

    enum CodingKeys: String, CodingKey {
        case hasData = "has_data"
        case debt7d  = "debt_7d"
        case debt30d = "debt_30d"
        case avgSleep7d     = "avg_sleep_7d"
        case target, trend
        case nightsToRecover = "nights_to_recover"
        case logged7d        = "logged_7d"
    }

    var isInDebt: Bool { (debt7d ?? 0) > 0 }

    var formattedDebt7d: String {
        guard let d = debt7d else { return "—" }
        if d <= 0 { return "+\(String(format: "%.1f", abs(d)))h" }
        return "\(String(format: "%.1f", d))h"
    }

    var trendLabel: String {
        switch trend {
        case "rembourser": return "Remboursement"
        case "creuser":    return "En hausse"
        default:           return "Stable"
        }
    }

    var trendIcon: String {
        switch trend {
        case "rembourser": return "arrow.down.circle.fill"
        case "creuser":    return "arrow.up.circle.fill"
        default:           return "equal.circle.fill"
        }
    }
}
