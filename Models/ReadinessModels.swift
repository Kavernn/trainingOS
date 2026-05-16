import Foundation

struct ReadinessResponse: Codable {
    let score: Int
    let verdict: String          // "go" | "moderate" | "rest"
    let why: String
    let adjustment: String?
    let progressionModifier: Double
    let modules: ReadinessModules
    let muscleRecovery: [String: MuscleGroupRecovery]
    let todaySession: String?
    let computedAt: String

    enum CodingKeys: String, CodingKey {
        case score, verdict, why, adjustment, modules
        case progressionModifier = "progression_modifier"
        case muscleRecovery      = "muscle_recovery"
        case todaySession        = "today_session"
        case computedAt          = "computed_at"
    }
}

struct ReadinessModules: Codable {
    let fatigue:   ReadinessModule
    let stress:    ReadinessModule
    let nutrition: ReadinessModule
    let pattern:   ReadinessModule
    let muscleRec: ReadinessModule

    enum CodingKeys: String, CodingKey {
        case fatigue, stress, nutrition, pattern
        case muscleRec = "muscle_rec"
    }
}

struct ReadinessModule: Codable {
    let score:  Int
    let label:  String
    let detail: String
}

struct MuscleGroupRecovery: Codable {
    let pct:            Int
    let hoursRemaining: Int
    let hoursSince:     Int
    let status:         String  // "ready" | "almost" | "partial"
    let label:          String

    enum CodingKeys: String, CodingKey {
        case pct, status, label
        case hoursRemaining = "hours_remaining"
        case hoursSince     = "hours_since"
    }
}

extension ReadinessResponse {
    var verdictColor: String {
        switch verdict {
        case "go":       return "green"
        case "moderate": return "yellow"
        default:         return "red"
        }
    }

    var verdictEmoji: String {
        switch verdict {
        case "go":       return "🟢"
        case "moderate": return "🟡"
        default:         return "🔴"
        }
    }

    var verdictLabel: String {
        switch verdict {
        case "go":       return "Go hard"
        case "moderate": return "Modère"
        default:         return "Rest day"
        }
    }
}
