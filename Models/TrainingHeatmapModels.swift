import Foundation

struct HeatmapWeek: Codable {
    let weekStart: String
    let days: [Int]

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
        case days
    }
}

struct AdherenceEntry: Codable {
    let planned: Int
    let actual: Int
    let rate: Double
}

struct TrainingHeatmapData: Codable {
    let hasData: Bool
    let weeks: [HeatmapWeek]
    let totalByDay: [Int]
    let adherenceByDay: [AdherenceEntry?]
    let sessionsTracked: Int
    let message: String

    enum CodingKeys: String, CodingKey {
        case hasData         = "has_data"
        case weeks
        case totalByDay      = "total_by_day"
        case adherenceByDay  = "adherence_by_day"
        case sessionsTracked = "sessions_tracked"
        case message
    }

    init(from decoder: Decoder) throws {
        let c            = try decoder.container(keyedBy: CodingKeys.self)
        hasData          = (try? c.decodeIfPresent(Bool.self,   forKey: .hasData))          ?? false
        weeks            = (try? c.decodeIfPresent([HeatmapWeek].self, forKey: .weeks))     ?? []
        totalByDay       = (try? c.decodeIfPresent([Int].self,  forKey: .totalByDay))        ?? Array(repeating: 0, count: 7)
        adherenceByDay   = (try? c.decodeIfPresent([AdherenceEntry?].self, forKey: .adherenceByDay)) ?? Array(repeating: nil, count: 7)
        sessionsTracked  = (try? c.decodeIfPresent(Int.self,    forKey: .sessionsTracked))  ?? 0
        message          = (try? c.decodeIfPresent(String.self, forKey: .message))          ?? ""
    }

    var trainingDayAdherence: [(dayIndex: Int, entry: AdherenceEntry)] {
        adherenceByDay.enumerated().compactMap { (i, e) in
            guard let e else { return nil }
            return (dayIndex: i, entry: e)
        }
    }

    var averageAdherenceRate: Double? {
        let entries = adherenceByDay.compactMap { $0 }
        guard !entries.isEmpty else { return nil }
        return entries.map(\.rate).reduce(0, +) / Double(entries.count)
    }
}
