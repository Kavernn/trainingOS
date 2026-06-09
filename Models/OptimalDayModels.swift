import Foundation

struct DayStats: Codable {
    let dow: Int
    let label: String
    let short: String
    let sessionCount: Int
    let avgRpe: Double?
    let completionRate: Int?

    var hasData: Bool { sessionCount >= 1 }
}

struct OptimalDayData: Codable {
    let hasData: Bool
    let bestDay: Int?
    let worstDay: Int?
    let byDay: [DayStats]
    let sessionsAnalyzed: Int

    var bestDayLabel: String {
        byDay.first(where: { $0.dow == bestDay })?.label ?? "—"
    }
    var worstDayLabel: String {
        byDay.first(where: { $0.dow == worstDay })?.label ?? "—"
    }
    var bestDayRpe: Double? {
        byDay.first(where: { $0.dow == bestDay })?.avgRpe
    }
}
