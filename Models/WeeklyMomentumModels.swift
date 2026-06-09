import Foundation

struct MomentumPillars: Codable {
    let training: Int
    let sleep: Int
    let nutrition: Int
    let stress: Int
}

struct MomentumWeekHistory: Codable {
    let weekStart: String
    let score: Int
}

struct WeeklyMomentumData: Codable {
    let hasData: Bool
    let score: Int?
    let pillars: MomentumPillars?
    let prevAvg: Int?
    let trendPct: Int?
    let weekStart: String?
    let history: [MomentumWeekHistory]
    let message: String

    var scoreColor: String {
        guard let s = score else { return "8E8E93" }
        if s >= 75 { return "34C759" }
        if s >= 50 { return "FF9500" }
        return "FF6B6B"
    }

    var trendIcon: String {
        guard let t = trendPct else { return "minus" }
        if t >= 5  { return "arrow.up.right" }
        if t <= -5 { return "arrow.down.right" }
        return "arrow.right"
    }

    var trendLabel: String {
        guard let t = trendPct else { return "—" }
        let sign = t >= 0 ? "+" : ""
        return "\(sign)\(t)%"
    }
}
