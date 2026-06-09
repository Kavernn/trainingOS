import Foundation

struct TemporalPatterns: Codable {
    let weakestDay: String
    let weakestDayScore: Double
    let strongestDay: String
    let strongestDayScore: Double
    let dayScores: [String: Double]
    let dayDetails: [String: DayDetail]
    let weakestFactors: [String]
    let suggestion: String
    let hasBaseline: Bool
    let zScores: [String: Double]

    enum CodingKeys: String, CodingKey {
        case suggestion, hasBaseline = "has_baseline"
        case weakestDay       = "weakest_day"
        case weakestDayScore  = "weakest_day_score"
        case strongestDay     = "strongest_day"
        case strongestDayScore = "strongest_day_score"
        case dayScores        = "day_scores"
        case dayDetails       = "day_details"
        case weakestFactors   = "weakest_factors"
        case zScores          = "z_scores"
    }

    init(from decoder: Decoder) throws {
        let c              = try decoder.container(keyedBy: CodingKeys.self)
        weakestDay         = (try? c.decodeIfPresent(String.self,              forKey: .weakestDay))        ?? "—"
        weakestDayScore    = (try? c.decodeIfPresent(Double.self,              forKey: .weakestDayScore))   ?? 0.0
        strongestDay       = (try? c.decodeIfPresent(String.self,              forKey: .strongestDay))      ?? "—"
        strongestDayScore  = (try? c.decodeIfPresent(Double.self,              forKey: .strongestDayScore)) ?? 0.0
        dayScores          = (try? c.decodeIfPresent([String: Double].self,    forKey: .dayScores))         ?? [:]
        dayDetails         = (try? c.decodeIfPresent([String: DayDetail].self, forKey: .dayDetails))        ?? [:]
        weakestFactors     = (try? c.decodeIfPresent([String].self,            forKey: .weakestFactors))    ?? []
        suggestion         = (try? c.decodeIfPresent(String.self,              forKey: .suggestion))        ?? ""
        hasBaseline        = (try? c.decodeIfPresent(Bool.self,                forKey: .hasBaseline))       ?? false
        zScores            = (try? c.decodeIfPresent([String: Double].self,    forKey: .zScores))           ?? [:]
    }

    static let dayOrder = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]

    var orderedDayScores: [(String, Double)] {
        Self.dayOrder.compactMap { day in
            guard let score = dayScores[day] else { return nil }
            return (day, score)
        }
    }
}

struct DayDetail: Codable {
    let workoutRate: Double
    let nutritionRate: Double
    let pssAvg: Double?
    let nOccurrences: Int

    enum CodingKeys: String, CodingKey {
        case workoutRate   = "workout_rate"
        case nutritionRate = "nutrition_rate"
        case pssAvg        = "pss_avg"
        case nOccurrences  = "n_occurrences"
    }
}
