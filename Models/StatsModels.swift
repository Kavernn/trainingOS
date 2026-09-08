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

// MARK: - Stats Cockpit

/// Civil dates from /api/stats/cockpit remain strings intentionally. They are
/// calendar dates, not instants in time, so they must not use the global
/// ISO-8601 Date decoder.
struct StatsDateWindow: Codable, Equatable {
    let start: String
    let end: String

    enum CodingKeys: String, CodingKey {
        case start, end
    }
}

enum StatsProgressionStatus: Codable, Equatable {
    case improving
    case stable
    case declining
    case insufficientData
    case unknown(String)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "improving": self = .improving
        case "stable": self = .stable
        case "declining": self = .declining
        case "insufficientData": self = .insufficientData
        default: self = .unknown(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .improving: try container.encode("improving")
        case .stable: try container.encode("stable")
        case .declining: try container.encode("declining")
        case .insufficientData: try container.encode("insufficientData")
        case .unknown(let value): try container.encode(value)
        }
    }
}

enum StatsInsufficiencyReason: Codable, Equatable {
    case nonComparableTrackingType
    case noValidExposure
    case insufficientBaselineExposures
    case insufficientRecentExposures
    case insufficientBothWindows
    case invalidBaseline
    case unknown(String)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "nonComparableTrackingType": self = .nonComparableTrackingType
        case "noValidExposure": self = .noValidExposure
        case "insufficientBaselineExposures": self = .insufficientBaselineExposures
        case "insufficientRecentExposures": self = .insufficientRecentExposures
        case "insufficientBothWindows": self = .insufficientBothWindows
        case "invalidBaseline": self = .invalidBaseline
        default: self = .unknown(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .nonComparableTrackingType: try container.encode("nonComparableTrackingType")
        case .noValidExposure: try container.encode("noValidExposure")
        case .insufficientBaselineExposures: try container.encode("insufficientBaselineExposures")
        case .insufficientRecentExposures: try container.encode("insufficientRecentExposures")
        case .insufficientBothWindows: try container.encode("insufficientBothWindows")
        case .invalidBaseline: try container.encode("invalidBaseline")
        case .unknown(let value): try container.encode(value)
        }
    }
}

enum StatsAttentionKind: Codable, Equatable {
    case noRecentImprovement
    case unknown(String)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = value == "noRecentImprovement" ? .noRecentImprovement : .unknown(value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .noRecentImprovement: try container.encode("noRecentImprovement")
        case .unknown(let value): try container.encode(value)
        }
    }
}

enum StatsTonnageCoverage: Codable, Equatable {
    case complete
    case partial
    case unavailable
    case unknown(String)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "complete": self = .complete
        case "partial": self = .partial
        case "unavailable": self = .unavailable
        default: self = .unknown(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .complete: try container.encode("complete")
        case .partial: try container.encode("partial")
        case .unavailable: try container.encode("unavailable")
        case .unknown(let value): try container.encode(value)
        }
    }
}

struct StatsProgressionStatusCounts: Codable, Equatable {
    let improving: Int
    let stable: Int
    let declining: Int
    let insufficientData: Int

    enum CodingKeys: String, CodingKey {
        case improving, stable, declining
        case insufficientData = "insufficient_data"
    }
}

struct StatsProgressionComparison: Codable, Equatable {
    let exerciseName: String
    let trackingType: String?
    let status: StatsProgressionStatus
    let baselineWindow: StatsDateWindow
    let recentWindow: StatsDateWindow
    let baselineBestE1RM: Double?
    let recentBestE1RM: Double?
    let absoluteDelta: Double?
    let relativeDelta: Double?
    let baselineExposureCount: Int
    let recentExposureCount: Int
    let baselineUsedLegacyFallback: Bool
    let recentUsedLegacyFallback: Bool
    let insufficiencyReason: StatsInsufficiencyReason?

    enum CodingKeys: String, CodingKey {
        case exerciseName = "exercise_name"
        case trackingType = "tracking_type"
        case status
        case baselineWindow = "baseline_window"
        case recentWindow = "recent_window"
        case baselineBestE1RM = "baseline_best_e1rm"
        case recentBestE1RM = "recent_best_e1rm"
        case absoluteDelta = "absolute_delta"
        case relativeDelta = "relative_delta"
        case baselineExposureCount = "baseline_exposure_count"
        case recentExposureCount = "recent_exposure_count"
        case baselineUsedLegacyFallback = "baseline_used_legacy_fallback"
        case recentUsedLegacyFallback = "recent_used_legacy_fallback"
        case insufficiencyReason = "insufficiency_reason"
    }
}

struct StatsAttentionObservation: Codable, Equatable {
    let kind: StatsAttentionKind
    let exerciseName: String
    let observationWindow: StatsDateWindow
    let lastExposureDate: String
    let daysSinceLastExposure: Int
    let validExposureCount: Int
    let coveredDays: Int
    let latestBestE1RM: Double

    enum CodingKeys: String, CodingKey {
        case kind
        case exerciseName = "exercise_name"
        case observationWindow = "observation_window"
        case lastExposureDate = "last_exposure_date"
        case daysSinceLastExposure = "days_since_last_exposure"
        case validExposureCount = "valid_exposure_count"
        case coveredDays = "covered_days"
        case latestBestE1RM = "latest_best_e1rm"
    }
}

struct StatsCockpitProgression: Codable, Equatable {
    let comparisonWindowDays: Int
    let baselineWindow: StatsDateWindow
    let recentWindow: StatsDateWindow
    let statusCounts: StatsProgressionStatusCounts
    let comparisons: [StatsProgressionComparison]
    let topMovers: [StatsProgressionComparison]
    let attention: [StatsAttentionObservation]

    enum CodingKeys: String, CodingKey {
        case comparisonWindowDays = "comparison_window_days"
        case baselineWindow = "baseline_window"
        case recentWindow = "recent_window"
        case statusCounts = "status_counts"
        case comparisons, attention
        case topMovers = "top_movers"
    }
}

struct StatsTonnageAggregate: Codable, Equatable {
    let value: Double?
    let applicableExposureCount: Int
    let calculableExposureCount: Int
    let coverage: StatsTonnageCoverage

    enum CodingKeys: String, CodingKey {
        case value, coverage
        case applicableExposureCount = "applicable_exposure_count"
        case calculableExposureCount = "calculable_exposure_count"
    }
}

struct StatsTrainingLoadSummary: Codable, Equatable {
    let period: StatsDateWindow
    let exposureCount: Int
    let sessionCount: Int
    let activeDayCount: Int
    let repsExposureCount: Int
    let validRepsSetCount: Int
    let tonnage: StatsTonnageAggregate

    enum CodingKeys: String, CodingKey {
        case period, tonnage
        case exposureCount = "exposure_count"
        case sessionCount = "session_count"
        case activeDayCount = "active_day_count"
        case repsExposureCount = "reps_exposure_count"
        case validRepsSetCount = "valid_reps_set_count"
    }
}

struct StatsWeeklyTrainingLoad: Codable, Equatable {
    let weekStart: String
    let weekEnd: String
    let coveredWindow: StatsDateWindow
    let isPartial: Bool
    let exposureCount: Int
    let sessionCount: Int
    let activeDayCount: Int
    let repsExposureCount: Int
    let validRepsSetCount: Int
    let tonnage: StatsTonnageAggregate

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
        case weekEnd = "week_end"
        case coveredWindow = "covered_window"
        case isPartial = "is_partial"
        case exposureCount = "exposure_count"
        case sessionCount = "session_count"
        case activeDayCount = "active_day_count"
        case repsExposureCount = "reps_exposure_count"
        case validRepsSetCount = "valid_reps_set_count"
        case tonnage
    }
}

struct StatsCockpitTrainingLoad: Codable, Equatable {
    let period: StatsDateWindow
    let summary: StatsTrainingLoadSummary
    let weekly: [StatsWeeklyTrainingLoad]
}

struct StatsMuscleMappingCoverage: Codable, Equatable {
    let totalExposureCount: Int
    let mappedExposureCount: Int
    let unmappedExposureCount: Int
    let repsExposureCount: Int
    let mappedRepsExposureCount: Int

    enum CodingKeys: String, CodingKey {
        case totalExposureCount = "total_exposure_count"
        case mappedExposureCount = "mapped_exposure_count"
        case unmappedExposureCount = "unmapped_exposure_count"
        case repsExposureCount = "reps_exposure_count"
        case mappedRepsExposureCount = "mapped_reps_exposure_count"
    }
}

struct StatsMuscleWorkload: Codable, Equatable {
    let muscle: String
    let directSetCount: Int
    let indirectSetCount: Int
    let directExposureCount: Int
    let indirectExposureCount: Int
    let sessionCount: Int
    let activeDayCount: Int
    let lastExposureDate: String

    enum CodingKeys: String, CodingKey {
        case muscle
        case directSetCount = "direct_set_count"
        case indirectSetCount = "indirect_set_count"
        case directExposureCount = "direct_exposure_count"
        case indirectExposureCount = "indirect_exposure_count"
        case sessionCount = "session_count"
        case activeDayCount = "active_day_count"
        case lastExposureDate = "last_exposure_date"
    }
}

struct StatsCockpitMuscles: Codable, Equatable {
    let period: StatsDateWindow
    let coverage: StatsMuscleMappingCoverage
    let workloads: [StatsMuscleWorkload]
}

struct StatsAnalyticsAdapterDiagnostics: Codable, Equatable {
    let queriedExposureCount: Int
    let analyticsExposureCount: Int
    let invalidRowCount: Int
    let missingTrackingTypeCount: Int
    let missingMuscleMappingCount: Int
    let legacyStrengthFallbackCount: Int
    let knownDeloadExposureCount: Int

    enum CodingKeys: String, CodingKey {
        case queriedExposureCount = "queried_exposure_count"
        case analyticsExposureCount = "analytics_exposure_count"
        case invalidRowCount = "invalid_row_count"
        case missingTrackingTypeCount = "missing_tracking_type_count"
        case missingMuscleMappingCount = "missing_muscle_mapping_count"
        case legacyStrengthFallbackCount = "legacy_strength_fallback_count"
        case knownDeloadExposureCount = "known_deload_exposure_count"
    }
}

struct StatsCockpitDataQuality: Codable, Equatable {
    let requestedRawPeriod: StatsDateWindow
    let adapter: StatsAnalyticsAdapterDiagnostics

    enum CodingKeys: String, CodingKey {
        case requestedRawPeriod = "requested_raw_period"
        case adapter
    }
}

struct StatsCockpitResponse: Codable, Equatable {
    let asOf: String
    let progression: StatsCockpitProgression
    let trainingLoad: StatsCockpitTrainingLoad
    let muscles: StatsCockpitMuscles
    let dataQuality: StatsCockpitDataQuality

    enum CodingKeys: String, CodingKey {
        case asOf = "as_of"
        case progression
        case trainingLoad = "training_load"
        case muscles
        case dataQuality = "data_quality"
    }
}
