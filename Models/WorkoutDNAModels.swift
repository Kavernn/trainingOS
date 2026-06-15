import Foundation

struct WorkoutDNAResponse: Codable {
    let period: DNAPeriod
    let archetype: DNAArchetype
    let ppl: DNAPPLBalance
    let intensity: DNAIntensity
    let consistency: DNAConsistency
    let recovery: DNARecovery
    let signatureLifts: [DNASignatureLift]
    let muscleDominants: [DNAMuscleDominant]?
    let movementPatterns: DNAMovementPatterns?
    let intensityTimeline: [DNAIntensityMonth]?
    let dnaSeed: String
    let computedAt: String

    enum CodingKeys: String, CodingKey {
        case period, archetype, ppl, intensity, consistency, recovery
        case signatureLifts    = "signature_lifts"
        case muscleDominants   = "muscle_dominants"
        case movementPatterns  = "movement_patterns"
        case intensityTimeline = "intensity_timeline"
        case dnaSeed           = "dna_seed"
        case computedAt        = "computed_at"
    }
}

struct DNAPeriod: Codable {
    let from: String
    let to: String
}

struct DNAArchetype: Codable {
    let key: String
    let label: String
    let tagline: String
}

struct DNAPPLBalance: Codable {
    let pushPct: Int
    let pullPct: Int
    let legsPct: Int
    let corePct: Int
    let otherPct: Int
    let balanceScore: Int
    let verdict: String

    enum CodingKeys: String, CodingKey {
        case verdict
        case pushPct      = "push_pct"
        case pullPct      = "pull_pct"
        case legsPct      = "legs_pct"
        case corePct      = "core_pct"
        case otherPct     = "other_pct"
        case balanceScore = "balance_score"
    }
}

struct DNAIntensity: Codable {
    let score: Int
    let label: String
    let forcePct: Int
    let hypertrophyPct: Int
    let endurancePct: Int
    let compoundPct: Int
    let isolationPct: Int

    enum CodingKeys: String, CodingKey {
        case score, label
        case forcePct       = "force_pct"
        case hypertrophyPct = "hypertrophy_pct"
        case endurancePct   = "endurance_pct"
        case compoundPct    = "compound_pct"
        case isolationPct   = "isolation_pct"
    }
}

struct DNAConsistency: Codable {
    let score: Int
    let sessionsPerWeek: Double
    let cv: Double
    let archetype: String
    let currentStreak: Int
    let longestStreak: Int
    let activeWeeksPct: Int
    let weeklyCounts: [Int]

    enum CodingKeys: String, CodingKey {
        case score, cv, archetype
        case sessionsPerWeek = "sessions_per_week"
        case currentStreak   = "current_streak"
        case longestStreak   = "longest_streak"
        case activeWeeksPct  = "active_weeks_pct"
        case weeklyCounts    = "weekly_counts"
    }
}

struct DNARecovery: Codable {
    let avgRestDays: Double
    let optimalRestDays: Double
    let ratio: Double
    let score: Int
    let verdict: String

    enum CodingKeys: String, CodingKey {
        case ratio, score, verdict
        case avgRestDays     = "avg_rest_days"
        case optimalRestDays = "optimal_rest_days"
    }
}

struct DNAMuscleDominant: Codable {
    let muscle: String
    let sets: Int
    let pct: Int
}

struct DNAMovementPatterns: Codable {
    let hasData: Bool
    let patterns: [DNAMovementPatternEntry]
    let ratios: DNAPatternRatios
    let diversityScore: Int
    let totalSets: Int?

    enum CodingKeys: String, CodingKey {
        case patterns
        case hasData        = "has_data"
        case ratios
        case diversityScore = "diversity_score"
        case totalSets      = "total_sets"
    }
}

struct DNAMovementPatternEntry: Codable, Identifiable {
    var id: String { pattern }
    let pattern: String
    let sets: Int
    let pct: Int
}

struct DNAPatternRatios: Codable {
    let hingeSquat: Double?
    let pushHorizVert: Double?

    enum CodingKeys: String, CodingKey {
        case hingeSquat    = "hinge_squat"
        case pushHorizVert = "push_horiz_vert"
    }
}

struct DNAIntensityMonth: Codable, Identifiable {
    var id: String { month }
    let month: String
    let strengthPct: Int
    let hypertrophyPct: Int
    let endurancePct: Int
    let totalSets: Int

    enum CodingKeys: String, CodingKey {
        case month
        case strengthPct    = "strength_pct"
        case hypertrophyPct = "hypertrophy_pct"
        case endurancePct   = "endurance_pct"
        case totalSets      = "total_sets"
    }
}

struct DNASignatureLift: Codable, Identifiable {
    var id: String { name }
    let name: String
    let sessionCount: Int
    let prLbs: Double
    let prReps: Int
    let prDate: String
    let firstDate: String
    let progressionPct: Double
    let recency: Int

    enum CodingKeys: String, CodingKey {
        case name, recency
        case sessionCount   = "session_count"
        case prLbs          = "pr_lbs"
        case prReps         = "pr_reps"
        case prDate         = "pr_date"
        case firstDate      = "first_date"
        case progressionPct = "progression_pct"
    }
}
