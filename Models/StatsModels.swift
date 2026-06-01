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

// MARK: - Adherence (4-pillar constance rings)
struct AdherenceData: Codable {
    let bodyPct:     Int
    let mindPct:     Int
    let fuelPct:     Int
    let spiritPct:   Int
    let daysElapsed: Int
    let period:      String
    let fuelDays:    Int?

    enum CodingKeys: String, CodingKey {
        case bodyPct     = "body_pct"
        case mindPct     = "mind_pct"
        case fuelPct     = "fuel_pct"
        case spiritPct   = "spirit_pct"
        case daysElapsed = "days_elapsed"
        case period
        case fuelDays    = "fuel_days"
    }
}

// MARK: - Season Comparison
struct SeasonCompStats: Codable {
    let title:         String?
    let volumeAvgWeek: Double?
    let sessionsCount: Int?
    let pssAvg:        Int?
    let weightDelta:   Double?
    let phoenixAvg:    Double?

    enum CodingKeys: String, CodingKey {
        case title
        case volumeAvgWeek = "volume_avg_week"
        case sessionsCount = "sessions_count"
        case pssAvg        = "pss_avg"
        case weightDelta   = "weight_delta"
        case phoenixAvg    = "phoenix_avg"
    }
}

struct SeasonComparisonData: Codable {
    let current:  SeasonCompStats?
    let previous: SeasonCompStats?
}

// MARK: - War Room Summary (stats subset for StatsView)
struct WarRoomSummaryStats: Codable {
    let totalVictories: Int
    let totalBattles:   Int
    let warStartDate:   String?

    enum CodingKeys: String, CodingKey {
        case totalVictories = "total_victories"
        case totalBattles   = "total_battles"
        case warStartDate   = "war_start_date"
    }
}

// MARK: - Relative Intensity (%1RM)
struct IntensityData: Codable {
    let avgPct1rm: Double?
    let zone:      String?
    let setsCount: Int

    enum CodingKeys: String, CodingKey {
        case avgPct1rm = "avg_pct_1rm"
        case zone
        case setsCount = "sets_count"
    }
}

// MARK: - Deload Status
struct DeloadStatusData: Codable {
    let recommande:       Bool
    let weeksSinceDeload: Int?
    let deloadActif:      Bool

    enum CodingKeys: String, CodingKey {
        case recommande
        case weeksSinceDeload = "weeks_since_deload"
        case deloadActif      = "deload_actif"
    }
}
