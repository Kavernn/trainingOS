import Foundation

// MARK: - Streak
struct StreakResponse: Codable {
    let currentStreak: Int
    let bestStreak:    Int
    let todayLogged:   Bool
    let streakAtRisk:  Bool

    enum CodingKeys: String, CodingKey {
        case currentStreak = "current_streak"
        case bestStreak    = "best_streak"
        case todayLogged   = "today_logged"
        case streakAtRisk  = "streak_at_risk"
    }
}
