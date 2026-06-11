import Foundation

struct SessionProgressionEntry: Codable {
    let sessionName: String
    let lastDate: String
    let lastVolume: Double?
    let lastDuration: Int?
    let lastRpe: Double?
    let baselineVolume: Double?
    let baselineDuration: Double?
    let volumeDeltaPct: Double?
    let durationDeltaPct: Double?
    let trend: String
    let occurrences: Int

    enum CodingKeys: String, CodingKey {
        case sessionName      = "session_name"
        case lastDate         = "last_date"
        case lastVolume       = "last_volume"
        case lastDuration     = "last_duration"
        case lastRpe          = "last_rpe"
        case baselineVolume   = "baseline_volume"
        case baselineDuration = "baseline_duration"
        case volumeDeltaPct   = "volume_delta_pct"
        case durationDeltaPct = "duration_delta_pct"
        case trend
        case occurrences
    }

    var trendIcon: String {
        switch trend {
        case "up":   return "arrow.up.right"
        case "down": return "arrow.down.right"
        default:     return "minus"
        }
    }

    var trendColor: String {
        switch trend {
        case "up":   return "trendPositive"
        case "down": return "trendNegative"
        default:     return "neutral"
        }
    }

    var relativeDate: String {
        guard let date = DateFormatter.isoDate.date(from: lastDate) else { return lastDate }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        switch days {
        case 0: return "Aujourd'hui"
        case 1: return "Hier"
        case 2...6: return "Il y a \(days)j"
        default:
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMM"
            formatter.locale = Locale(identifier: "fr_CA")
            return formatter.string(from: date)
        }
    }
}

struct SessionProgressionData: Codable {
    let hasData: Bool
    let sessions: [SessionProgressionEntry]

    enum CodingKeys: String, CodingKey {
        case hasData = "has_data"
        case sessions
    }

    init(from decoder: Decoder) throws {
        let c    = try decoder.container(keyedBy: CodingKeys.self)
        hasData  = (try? c.decodeIfPresent(Bool.self, forKey: .hasData)) ?? false
        sessions = (try? c.decodeIfPresent([SessionProgressionEntry].self, forKey: .sessions)) ?? []
    }
}
