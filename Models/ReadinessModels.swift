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
    // Commit 4 — baseline HRV unifiée : source unique = backend.
    let hrvStatus: HRVStatus?

    enum CodingKeys: String, CodingKey {
        case score, verdict, why, adjustment, modules
        case progressionModifier = "progression_modifier"
        case muscleRecovery      = "muscle_recovery"
        case todaySession        = "today_session"
        case hrvStatus           = "hrv_status"
    }
}

/// Statut HRV calculé par hrv_engine.compute_hrv_analysis (backend, baseline
/// 7j, sensitivity user_profile). Consommé par DashboardSignalEngine pour
/// le bandeau critique — plus de seuil local. Futurs consommateurs à migrer
/// (commit 5 backlog) : RecoveryPerformanceBanner, RecoveryView.
struct HRVStatus: Codable {
    let score:      Double?      // today/baseline_7d × 100 (0-150+)
    let zone:       String?      // "green" | "orange" | "red"
    let todayRmssd: Double?
    let baseline7d: Double?

    enum CodingKeys: String, CodingKey {
        case score, zone
        case todayRmssd = "today_rmssd"
        case baseline7d = "baseline_7d"
    }
}

struct ReadinessModules: Codable {
    let hrv:           ReadinessModule
    let rhr:           ReadinessModule
    let acwr:          ReadinessModule
    let sleepQuality:  ReadinessModule
    let sleepDuration: ReadinessModule
    let subjective:    ReadinessModule
    let muscleRec:     ReadinessModule
    let nutrition:     ReadinessModule
    let pattern:       ReadinessModule

    enum CodingKeys: String, CodingKey {
        case hrv, rhr, acwr, subjective, nutrition, pattern
        case sleepQuality  = "sleep_quality"
        case sleepDuration = "sleep_duration"
        case muscleRec     = "muscle_rec"
    }
}

struct ReadinessModule: Codable {
    let score:  Int?   // nil = données insuffisantes → afficher "—"
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
