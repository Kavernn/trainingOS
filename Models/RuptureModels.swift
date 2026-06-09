import Foundation

enum RuptureLevel {
    case nominal, vigilance, elevated, critical
}

struct RuptureContext: Codable {
    let workoutCount: Int
    let avgSleep: Double?
    let avgPss: Double?

    enum CodingKeys: String, CodingKey {
        case workoutCount = "workout_count"
        case avgSleep     = "avg_sleep"
        case avgPss       = "avg_pss"
    }
}

struct RuptureRisk: Codable {
    let score: Int
    let signals: [String]
    let signalCount: Int
    let similarEpisodes: Int
    let totalEpisodes: Int
    let message: String
    let hasData: Bool
    let context: RuptureContext?

    enum CodingKeys: String, CodingKey {
        case score, signals, message, context
        case signalCount     = "signal_count"
        case similarEpisodes = "similar_episodes"
        case totalEpisodes   = "total_episodes"
        case hasData         = "has_data"
    }

    var riskLevel: RuptureLevel {
        switch score {
        case 0..<20:  return .nominal
        case 20..<40: return .vigilance
        case 40..<60: return .elevated
        default:      return .critical
        }
    }

    var riskColorHex: String {
        switch riskLevel {
        case .nominal:   return "34C759"
        case .vigilance: return "FF9500"
        case .elevated:  return "FF6B6B"
        case .critical:  return "FF3B30"
        }
    }

    func signalLabel(_ signal: String) -> String {
        switch signal {
        case "sommeil_court":          return "Sommeil insuffisant"
        case "stress_croissant":       return "Stress élevé"
        case "entrainements_manques":  return "Entraînements absents"
        case "nutrition_absente":      return "Nutrition non loggée"
        default:                       return signal
        }
    }

    func signalIcon(_ signal: String) -> String {
        switch signal {
        case "sommeil_court":          return "moon.zzz.fill"
        case "stress_croissant":       return "brain.head.profile"
        case "entrainements_manques":  return "figure.strengthtraining.traditional"
        case "nutrition_absente":      return "fork.knife"
        default:                       return "exclamationmark.circle"
        }
    }
}
