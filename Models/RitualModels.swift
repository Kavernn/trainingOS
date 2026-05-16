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

    enum CodingKeys: String, CodingKey {
        case ok, outcome
        case phoenixStreak      = "phoenix_streak"
        case phoenixBest        = "phoenix_best"
        case phoenixTotalBurned = "phoenix_total_burned"
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
