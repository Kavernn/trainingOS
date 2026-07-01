import Foundation

// MARK: - Config

struct WarRoomConfig: Codable {
    var warStartDate: String?
    var substanceLabel: String
    var integrationPhoenix: Bool
    var integrationReadiness: Bool
    var integrationAiCoach: Bool

    enum CodingKeys: String, CodingKey {
        case warStartDate        = "war_start_date"
        case substanceLabel      = "substance_label"
        case integrationPhoenix  = "integration_phoenix"
        case integrationReadiness = "integration_readiness"
        case integrationAiCoach  = "integration_ai_coach"
    }
}

// MARK: - Battle

enum BattleStatus: String, Codable, CaseIterable {
    case victory, lost, active
}

struct WarRoomBattle: Codable, Identifiable {
    let id: String
    let date: String
    var status: BattleStatus
    var notes: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, date, status, notes
        case createdAt = "created_at"
    }
}

// MARK: - Trigger

enum TriggerContext: String, Codable, CaseIterable {
    case stress, social, boredom, pain, celebration, exhaustion, custom

    var label: String {
        switch self {
        case .stress:       return "Stress"
        case .social:       return "Social"
        case .boredom:      return "Ennui"
        case .pain:         return "Douleur"
        case .celebration:  return "Célébration"
        case .exhaustion:   return "Fatigue"
        case .custom:       return "Autre"
        }
    }
}

struct WarRoomTrigger: Codable, Identifiable {
    let id: String
    let date: String
    let loggedAt: String?
    let context: TriggerContext
    let contextNote: String?
    let intensity: Int
    let yielded: Bool
    let heldWith: [String]?

    enum CodingKeys: String, CodingKey {
        case id, date, context, intensity, yielded
        case loggedAt    = "logged_at"
        case contextNote = "context_note"
        case heldWith    = "held_with"
    }
}

// MARK: - Arsenal

enum ArsenalCategory: String, Codable, CaseIterable {
    case call, physical, breath, mental, environment, other

    var label: String {
        switch self {
        case .call:        return "Appel"
        case .physical:    return "Physique"
        case .breath:      return "Respiration"
        case .mental:      return "Mental"
        case .environment: return "Environnement"
        case .other:       return "Autre"
        }
    }

    var icon: String {
        switch self {
        case .call:        return "phone.fill"
        case .physical:    return "figure.run"
        case .breath:      return "wind"
        case .mental:      return "brain.head.profile"
        case .environment: return "house.fill"
        case .other:       return "bolt.fill"
        }
    }
}

struct WarRoomArsenalItem: Codable, Identifiable {
    let id: String
    let label: String
    let category: ArsenalCategory
    var useCount: Int
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, label, category
        case useCount  = "use_count"
        case sortOrder = "sort_order"
    }
}

// MARK: - Summary

struct WarRoomSummary: Codable {
    let victoryStreak: Int
    let bestStreak: Int
    let totalVictories: Int
    let totalBattles: Int
    let todayStatus: BattleStatus?
    let warStartDate: String?
    let warDays: Int
    let winRate30d: Int?
    let winRate90d: Int?
    let winRateWeek: Int?

    enum CodingKeys: String, CodingKey {
        case victoryStreak  = "victory_streak"
        case bestStreak     = "best_streak"
        case totalVictories = "total_victories"
        case totalBattles   = "total_battles"
        case todayStatus    = "today_status"
        case warStartDate   = "war_start_date"
        case warDays        = "war_days"
        case winRate30d     = "win_rate_30d"
        case winRate90d     = "win_rate_90d"
        case winRateWeek    = "win_rate_week"
    }
}

// MARK: - Patterns

struct WarRoomInsight: Codable, Identifiable {
    let type: String
    let title: String
    let body: String
    let detail: String?
    var id: String { type }
}

struct WarRoomPatterns: Codable {
    let insights: [WarRoomInsight]
    let totalTriggers: Int
    let enoughData: Bool

    enum CodingKeys: String, CodingKey {
        case insights
        case totalTriggers = "total_triggers"
        case enoughData    = "enough_data"
    }
}

// MARK: - Today Status

struct WarRoomTodayStatus: Codable {
    let active: Bool
    let hasResult: Bool
    let hasTemptation: Bool
    let resultLoggedAt: String?
    let temptationLoggedAt: String?

    enum CodingKeys: String, CodingKey {
        case active
        case hasResult          = "has_result"
        case hasTemptation      = "has_temptation"
        case resultLoggedAt     = "result_logged_at"
        case temptationLoggedAt = "temptation_logged_at"
    }

    static let inactive = WarRoomTodayStatus(
        active: false, hasResult: false, hasTemptation: false,
        resultLoggedAt: nil, temptationLoggedAt: nil
    )
}

// MARK: - War Map

struct WarMapDay: Codable {
    let date: String
    let status: BattleStatus?
}

struct WarMapMonth: Codable, Identifiable {
    let month: String
    let days: [WarMapDay]
    var id: String { month }
}
