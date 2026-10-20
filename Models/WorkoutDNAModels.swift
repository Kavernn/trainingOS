import Foundation

struct WorkoutDNAResponse: Codable {
    let period: DNAPeriod
    let archetype: DNAArchetype
    let ppl: DNAPPLBalance
    let intensity: DNAIntensity
    let consistency: DNAConsistency
    let recovery: DNARecovery              // legacy — supprimé après e3
    let sessionSpacing: DNASessionSpacing?
    let signatureLifts: [DNASignatureLift]
    let muscleDominants: [DNAMuscleDominant]?
    let muscleDominantsMeta: DNAMuscleDominantsMeta?
    let movementPatterns: DNAMovementPatterns?
    let intensityTimeline: [DNAIntensityMonth]?
    let dnaSeed: String
    let computedAt: String

    enum CodingKeys: String, CodingKey {
        case period, archetype, ppl, intensity, consistency, recovery
        case sessionSpacing      = "session_spacing"
        case signatureLifts      = "signature_lifts"
        case muscleDominants     = "muscle_dominants"
        case muscleDominantsMeta = "muscle_dominants_meta"
        case movementPatterns    = "movement_patterns"
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
    /// Backend lot f : `false` → piliers insuffisants ou en erreur, l'UI
    /// doit afficher un empty state au lieu de l'archétype calculé.
    /// Absent (nil) côté payload avant lot f → traité comme disponible.
    let available: Bool?
}

struct DNAPPLBalance: Codable {
    // Valeurs présentes uniquement si insufficientData=false ET pas d'error.
    let pushPct: Int?
    let pullPct: Int?
    let legsPct: Int?
    let corePct: Int?
    let otherPct: Int?
    let balanceScore: Int?
    let verdict: String?
    // Meta — toujours présentes.
    let insufficientData: Bool?
    let nSessions: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case verdict
        case pushPct          = "push_pct"
        case pullPct          = "pull_pct"
        case legsPct          = "legs_pct"
        case corePct          = "core_pct"
        case otherPct         = "other_pct"
        case balanceScore     = "balance_score"
        case insufficientData = "insufficient_data"
        case nSessions        = "n_sessions"
        case error
    }
}

struct DNAIntensity: Codable {
    let score: Int?
    let label: String?
    let forcePct: Int?
    let hypertrophyPct: Int?
    let endurancePct: Int?
    let compoundPct: Int?
    let isolationPct: Int?
    let insufficientData: Bool?
    let nSessions: Int?
    let excludedNoLoadProfile: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case score, label, error
        case forcePct             = "force_pct"
        case hypertrophyPct       = "hypertrophy_pct"
        case endurancePct         = "endurance_pct"
        case compoundPct          = "compound_pct"
        case isolationPct         = "isolation_pct"
        case insufficientData     = "insufficient_data"
        case nSessions            = "n_sessions"
        case excludedNoLoadProfile = "excluded_no_load_profile"
    }
}

struct DNAConsistency: Codable {
    let score: Int
    let sessionsPerWeek: Double
    let cv: Double
    let archetype: String
    let weeklyStreakCurrent: Int    // source unique : /api/stats/streaks
    let weeklyStreakBest: Int       // record historique weekly ISO
    let activeWeeksPct: Int
    let weeklyCounts: [Int]

    enum CodingKeys: String, CodingKey {
        case score, cv, archetype
        case sessionsPerWeek      = "sessions_per_week"
        case weeklyStreakCurrent  = "weekly_streak_current"
        case weeklyStreakBest     = "weekly_streak_best"
        case activeWeeksPct       = "active_weeks_pct"
        case weeklyCounts         = "weekly_counts"
    }
}

// Legacy — à retirer étape e3 (backend) une fois sessionSpacing adopté partout.
struct DNARecovery: Codable {
    let avgRestDays: Double?
    let optimalRestDays: Double?
    let ratio: Double?
    let score: Int?
    let verdict: String?

    enum CodingKeys: String, CodingKey {
        case ratio, score, verdict
        case avgRestDays     = "avg_rest_days"
        case optimalRestDays = "optimal_rest_days"
    }
}

/// Nouvelle section lot e — remplace l'ancienne "récupération DNA"
/// (score inventé, verdict "Optimal" fantôme). Expose uniquement ce qu'elle
/// mesure vraiment : espacement médian entre séances actives dans la fenêtre
/// DNA, décharges exclues au numérateur ET au dénominateur.
struct DNASessionSpacing: Codable {
    let medianDays: Double?
    let p25Days: Double?
    let p75Days: Double?
    let nSessions: Int
    let nGaps: Int
    let excludedDeloadSessions: Int?
    let invalidDates: Int?
    let insufficientData: Bool?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case error
        case medianDays             = "median_days"
        case p25Days                = "p25_days"
        case p75Days                = "p75_days"
        case nSessions              = "n_sessions"
        case nGaps                  = "n_gaps"
        case excludedDeloadSessions = "excluded_deload_sessions"
        case invalidDates           = "invalid_dates"
        case insufficientData       = "insufficient_data"
    }
}

struct DNAMuscleDominant: Codable {
    let muscle: String
    /// Legacy — round(effectiveSets). Backend l'émet encore pour compat, iOS
    /// n'affiche plus que effectiveSets.
    let sets: Int?
    /// Séries effectives / semaine (direct + 0,5 × indirect, hors décharge
    /// au numérateur ET au dénominateur) — même source que cockpit.
    let effectiveSets: Double?
    let pct: Int

    enum CodingKeys: String, CodingKey {
        case muscle, sets, pct
        case effectiveSets = "effective_sets"
    }
}

struct DNAMuscleDominantsMeta: Codable {
    let nSessions: Int
    let insufficientData: Bool
    let excludedFullDeload: Int?

    enum CodingKeys: String, CodingKey {
        case nSessions            = "n_sessions"
        case insufficientData     = "insufficient_data"
        case excludedFullDeload   = "excluded_full_deload"
    }
}

struct DNAMovementPatterns: Codable {
    let hasData: Bool
    let patterns: [DNAMovementPatternEntry]
    let ratios: DNAPatternRatios
    let diversityScore: Int
    let totalSets: Int?
    let insufficientData: Bool?
    let nSessions: Int?
    let excludedNoPattern: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case patterns, ratios, error
        case hasData           = "has_data"
        case diversityScore    = "diversity_score"
        case totalSets         = "total_sets"
        case insufficientData  = "insufficient_data"
        case nSessions         = "n_sessions"
        case excludedNoPattern = "excluded_no_pattern"
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
    /// Nombre de séances distinctes dans la fenêtre DNA, hors décharge.
    /// Classement DNA = par fréquence desc, tie-break par lastDate desc.
    let sessionCount: Int
    /// Legacy = pr_weight_lbs — backend l'émet pour compat, iOS n'affiche
    /// plus que prEIrmLbs.
    let prLbs: Double?
    /// e1RM = exercise_prs.pr_e1rm_lbs (même source que PR Tracker).
    let prEIrmLbs: Double?
    let prReps: Int
    let prDate: String
    /// Première séance observée dans la fenêtre DNA (pour "depuis le ...").
    let firstDate: String
    /// Dernière séance observée dans la fenêtre DNA (tie-break ranking).
    let lastDate: String?
    /// (best_e1rm des 30 premiers jours → best_e1rm des 30 derniers jours
    /// de la fenêtre DNA) × 100. `nil` si une des deux sous-fenêtres est
    /// vide — jamais 0 silencieux.
    let progressionPct: Double?

    enum CodingKeys: String, CodingKey {
        case name
        case sessionCount   = "session_count"
        case prLbs          = "pr_lbs"
        case prEIrmLbs      = "pr_e1rm_lbs"
        case prReps         = "pr_reps"
        case prDate         = "pr_date"
        case firstDate      = "first_date"
        case lastDate       = "last_date"
        case progressionPct = "progression_pct"
    }
}
