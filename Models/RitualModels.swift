import Foundation

struct RitualToday: Codable {
    let date: String
    let truth: String
    let truthType: String
    let intention: String?
    let morningAt: String?
    let outcome: String?          // "burned" | "survived" | nil
    let eveningAt: String?
    let carryCount: Int
    let carriedFrom: String?
    let carriedIntention: String? // haunting demon from a prior survived day
    let suggestions: [String]
    let phoenixStreak: Int
    let phoenixBest: Int
    let phoenixTotalBurned: Int
    let demons: [RitualDemon]
    // Micro-ritual checklist (D)
    let weightLogged: Bool
    let hydrationDone: Bool
    let mobilityDone: Bool
    let proteinDone: Bool
    let gratitude: String?
    let winddownDone: Bool
    let coldDone: Bool
    let reflection: String?
    let yesterdayIntention: String?   // tomorrow_intention saisie hier soir
    let yesterdayOutcome: String?     // outcome d'hier soir (burned/survived)
    let yesterdayEveningAt: String?   // heure à laquelle l'intention a été prise hier soir

    var morningDone: Bool  { morningAt != nil }
    var eveningDone: Bool  { eveningAt != nil }
    var burnedToday: Bool  { outcome == "burned" }
    var survivedToday: Bool { outcome == "survived" }

    enum CodingKeys: String, CodingKey {
        case date, truth, intention, outcome, suggestions, demons
        case truthType          = "truth_type"
        case morningAt          = "morning_at"
        case eveningAt          = "evening_at"
        case carryCount         = "carry_count"
        case carriedFrom        = "carried_from"
        case carriedIntention   = "carried_intention"
        case phoenixStreak      = "phoenix_streak"
        case phoenixBest        = "phoenix_best"
        case phoenixTotalBurned = "phoenix_total_burned"
        case weightLogged          = "weight_logged"
        case hydrationDone         = "hydration_done"
        case mobilityDone          = "mobility_done"
        case proteinDone           = "protein_done"
        case gratitude             = "gratitude"
        case winddownDone          = "winddown_done"
        case coldDone              = "cold_done"
        case reflection            = "reflection"
        case yesterdayIntention    = "yesterday_intention"
        case yesterdayOutcome      = "yesterday_outcome"
        case yesterdayEveningAt    = "yesterday_evening_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date              = (try? c.decode(String.self, forKey: .date))          ?? ""
        truth             = (try? c.decode(String.self, forKey: .truth))         ?? ""
        truthType         = (try? c.decode(String.self, forKey: .truthType))     ?? "default"
        intention         = try? c.decode(String.self, forKey: .intention)
        morningAt         = try? c.decode(String.self, forKey: .morningAt)
        outcome           = try? c.decode(String.self, forKey: .outcome)
        eveningAt         = try? c.decode(String.self, forKey: .eveningAt)
        carryCount        = (try? c.decode(Int.self,    forKey: .carryCount))    ?? 0
        carriedFrom       = try? c.decode(String.self, forKey: .carriedFrom)
        carriedIntention  = try? c.decode(String.self, forKey: .carriedIntention)
        suggestions       = (try? c.decode([String].self, forKey: .suggestions)) ?? []
        phoenixStreak     = (try? c.decode(Int.self,    forKey: .phoenixStreak)) ?? 0
        phoenixBest       = (try? c.decode(Int.self,    forKey: .phoenixBest))   ?? 0
        phoenixTotalBurned = (try? c.decode(Int.self,   forKey: .phoenixTotalBurned)) ?? 0
        demons            = (try? c.decode([RitualDemon].self, forKey: .demons)) ?? []
        weightLogged  = (try? c.decode(Bool.self, forKey: .weightLogged))  ?? false
        hydrationDone = (try? c.decode(Bool.self, forKey: .hydrationDone)) ?? false
        mobilityDone  = (try? c.decode(Bool.self, forKey: .mobilityDone))  ?? false
        proteinDone   = (try? c.decode(Bool.self, forKey: .proteinDone))   ?? false
        gratitude          = try? c.decode(String.self, forKey: .gratitude)
        winddownDone       = (try? c.decode(Bool.self, forKey: .winddownDone))       ?? false
        coldDone           = (try? c.decode(Bool.self, forKey: .coldDone))           ?? false
        reflection         = try? c.decode(String.self, forKey: .reflection)
        yesterdayIntention  = try? c.decode(String.self, forKey: .yesterdayIntention)
        yesterdayOutcome    = try? c.decode(String.self, forKey: .yesterdayOutcome)
        yesterdayEveningAt  = try? c.decode(String.self, forKey: .yesterdayEveningAt)
    }
}

struct RitualDemon: Codable, Identifiable {
    var id: String { date }
    let date: String
    let intention: String
    let carryCount: Int
    let truth: String?

    enum CodingKeys: String, CodingKey {
        case date, intention, truth
        case carryCount = "carry_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date       = (try? c.decode(String.self, forKey: .date))      ?? ""
        intention  = (try? c.decode(String.self, forKey: .intention)) ?? ""
        carryCount = (try? c.decode(Int.self,    forKey: .carryCount)) ?? 0
        truth      = try? c.decode(String.self, forKey: .truth)
    }
}

struct RitualEveningResult: Codable {
    let ok: Bool
    let outcome: String
    let phoenixStreak: Int
    let phoenixBest: Int
    let phoenixTotalBurned: Int
    let intentionMatchedSession: Bool

    enum CodingKeys: String, CodingKey {
        case ok, outcome
        case phoenixStreak      = "phoenix_streak"
        case phoenixBest        = "phoenix_best"
        case phoenixTotalBurned = "phoenix_total_burned"
        case intentionMatchedSession = "intention_matched_session"
    }

    init(ok: Bool, outcome: String, phoenixStreak: Int, phoenixBest: Int,
         phoenixTotalBurned: Int, intentionMatchedSession: Bool) {
        self.ok = ok; self.outcome = outcome; self.phoenixStreak = phoenixStreak
        self.phoenixBest = phoenixBest; self.phoenixTotalBurned = phoenixTotalBurned
        self.intentionMatchedSession = intentionMatchedSession
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok                    = (try? c.decode(Bool.self,   forKey: .ok))                    ?? false
        outcome               = (try? c.decode(String.self, forKey: .outcome))               ?? ""
        phoenixStreak         = (try? c.decode(Int.self,    forKey: .phoenixStreak))         ?? 0
        phoenixBest           = (try? c.decode(Int.self,    forKey: .phoenixBest))           ?? 0
        phoenixTotalBurned    = (try? c.decode(Int.self,    forKey: .phoenixTotalBurned))    ?? 0
        intentionMatchedSession = (try? c.decode(Bool.self, forKey: .intentionMatchedSession)) ?? false
    }
}

struct PhoenixStats: Codable {
    let phoenixStreak: Int
    let phoenixBest: Int
    let phoenixTotalBurned: Int

    enum CodingKeys: String, CodingKey {
        case phoenixStreak      = "phoenix_streak"
        case phoenixBest        = "phoenix_best"
        case phoenixTotalBurned = "phoenix_total_burned"
    }
}

struct RitualStats: Codable {
    let completionRate7d: Double
    let burnRate7d: Double
    let completionRate30d: Double
    let burnRate30d: Double
    let phoenixStreak: Int
    let phoenixBest: Int
    let phoenixTotalBurned: Int
    let weeklyCompletions: [RitualWeeklyEntry]

    enum CodingKeys: String, CodingKey {
        case completionRate7d  = "completion_rate_7d"
        case burnRate7d        = "burn_rate_7d"
        case completionRate30d = "completion_rate_30d"
        case burnRate30d       = "burn_rate_30d"
        case phoenixStreak     = "phoenix_streak"
        case phoenixBest       = "phoenix_best"
        case phoenixTotalBurned = "phoenix_total_burned"
        case weeklyCompletions = "weekly_completions"
    }
}

struct RitualWeeklyEntry: Codable, Identifiable {
    var id: String { week }
    let week: String
    let completed: Int
    let burned: Int
}

struct RitualCorrelations: Codable {
    let burnVsRpe: CorrelationPair
    let burnVsSleep: CorrelationPair

    enum CodingKeys: String, CodingKey {
        case burnVsRpe   = "burn_vs_rpe"
        case burnVsSleep = "burn_vs_sleep"
    }
}

struct CorrelationPair: Codable {
    let burnNext: Double?
    let surviveNext: Double?
    let nBurn: Int
    let nSurvive: Int

    enum CodingKeys: String, CodingKey {
        case burnNext    = "burn_next_rpe"
        case surviveNext = "survive_next_rpe"
        case nBurn       = "n_burn"
        case nSurvive    = "n_survive"
    }
}

struct RitualHistoryEntry: Codable, Identifiable {
    var id: String { date }
    let date: String
    let truth: String?
    let intention: String?
    let tomorrowIntention: String?
    let outcome: String?
    let carryCount: Int
    let reflection: String?
    let morningAt: String?
    let eveningAt: String?

    enum CodingKeys: String, CodingKey {
        case date, truth, intention, outcome, reflection
        case tomorrowIntention = "tomorrow_intention"
        case carryCount        = "carry_count"
        case morningAt         = "morning_at"
        case eveningAt         = "evening_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date              = (try? c.decode(String.self, forKey: .date))      ?? ""
        truth             = try? c.decode(String.self, forKey: .truth)
        intention         = try? c.decode(String.self, forKey: .intention)
        tomorrowIntention = try? c.decode(String.self, forKey: .tomorrowIntention)
        outcome           = try? c.decode(String.self, forKey: .outcome)
        carryCount        = (try? c.decode(Int.self,   forKey: .carryCount)) ?? 0
        reflection        = try? c.decode(String.self, forKey: .reflection)
        morningAt         = try? c.decode(String.self, forKey: .morningAt)
        eveningAt         = try? c.decode(String.self, forKey: .eveningAt)
    }
}

struct RitualHistoryPage: Codable {
    let entries: [RitualHistoryEntry]
    let total: Int
    let limit: Int
    let offset: Int
}
