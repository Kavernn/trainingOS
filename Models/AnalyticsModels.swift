import Foundation
import SwiftUI

// MARK: - Insights
struct InsightEntry: Codable, Identifiable {
    var id: String { type + title }
    let type: String    // "fatigue" | "stagnation" | "pr_near" | "consistency" | "milestone"
    let level: String   // "warning" | "info" | "success"
    let icon: String
    let title: String
    let message: String
}

// MARK: - Deload
struct DeloadReport: Codable {
    let deloadActif: Bool
    let stagnants: [String]
    let fatigueRpe: Bool
    let recommande: Bool
    let poidsDeload: [String: Double]
    let fatigueScore: Int
    let streakDays: Int
    let rpeAvg7j: Double?

    enum CodingKeys: String, CodingKey {
        case deloadActif  = "deload_actif"
        case stagnants
        case fatigueRpe   = "fatigue_rpe"
        case recommande
        case poidsDeload  = "poids_deload"
        case fatigueScore = "fatigue_score"
        case streakDays   = "streak_days"
        case rpeAvg7j     = "rpe_avg_7j"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deloadActif  = try c.decodeIfPresent(Bool.self,           forKey: .deloadActif)  ?? false
        // API may return either [String] or [{exercise: String, ...}] depending on cache age
        if let strings = try? c.decodeIfPresent([String].self, forKey: .stagnants) {
            stagnants = strings ?? []
        } else {
            struct StagnantDict: Decodable { let exercise: String }
            stagnants = (try? c.decodeIfPresent([StagnantDict].self, forKey: .stagnants))?.map(\.exercise) ?? []
        }
        fatigueRpe   = try c.decodeIfPresent(Bool.self,           forKey: .fatigueRpe)   ?? false
        recommande   = try c.decodeIfPresent(Bool.self,           forKey: .recommande)   ?? false
        poidsDeload  = try c.decodeIfPresent([String: Double].self, forKey: .poidsDeload) ?? [:]
        fatigueScore = try c.decodeIfPresent(Int.self,            forKey: .fatigueScore) ?? 0
        streakDays   = try c.decodeIfPresent(Int.self,            forKey: .streakDays)   ?? 0
        rpeAvg7j     = try c.decodeIfPresent(Double.self,         forKey: .rpeAvg7j)
    }

    /// 0 = OK, 1 = attention (score ≥ 65), 2 = critique (score ≥ 75 sur 7–30j)
    var fatigueLevel: Int {
        if fatigueScore >= 75 { return 2 }
        if fatigueScore >= 65 { return 1 }
        return 0
    }
}

// MARK: - Health Dashboard
struct DailyHealthSummary: Codable, Identifiable {
    var id: String { date }
    let date: String

    let steps: Int?
    let sleepDuration: Double?
    let sleepQuality: Double?
    let restingHeartRate: Double?
    let hrv: Double?
    let soreness: Double?
    let recoveryScore: Double?
    let heartRateAvg: Double?

    let bodyWeight: Double?
    let bodyFatPct: Double?
    let waistCm: Double?

    let distanceKm: Double?
    let activeMinutes: Double?
    let pace: String?
    let cardioType: String?
    let cardioCalories: Double?

    let trainingRpe: Double?
    let trainingDurationMin: Double?
    let trainingEnergyPre: Int?
    let trainingExercises: [String]?

    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let meals: Int?

    let dataSources: [String]?

    enum CodingKeys: String, CodingKey {
        case date, steps, soreness, pace, calories, protein, carbs, fat, meals, hrv
        case sleepDuration      = "sleep_duration"
        case sleepQuality       = "sleep_quality"
        case restingHeartRate   = "resting_heart_rate"
        case recoveryScore      = "recovery_score"
        case heartRateAvg       = "heart_rate_avg"
        case bodyWeight         = "body_weight"
        case bodyFatPct         = "body_fat_pct"
        case waistCm            = "waist_cm"
        case distanceKm         = "distance_km"
        case activeMinutes      = "active_minutes"
        case cardioType         = "cardio_type"
        case cardioCalories     = "cardio_calories"
        case trainingRpe        = "training_rpe"
        case trainingDurationMin = "training_duration_min"
        case trainingEnergyPre  = "training_energy_pre"
        case trainingExercises  = "training_exercises"
        case dataSources        = "data_sources"
    }
}

// MARK: - ACWR
struct ACWRData: Codable {
    let ratio: Double
    let acuteLoad: Double
    let chronicLoad: Double
    // zone est non-optionnel : si le backend retourne zone:null, JSONDecoder throw
    // → acwr reste nil → la condition "if let a = acwr" ne s'exécute pas → safe.
    let zone: ACWRZone
    let trend: [ACWRWeek]
    let confidence: String  // "low" | "moderate" | "high"
    let daysOfData: Int

    enum CodingKeys: String, CodingKey {
        case ratio, zone, trend, confidence
        case acuteLoad   = "acute_load"
        case chronicLoad = "chronic_load"
        case daysOfData  = "days_of_data"
    }
}

struct ACWRZone: Codable {
    let code: String
    let label: String
    let color: String
    let recommendation: String
}

struct ACWRWeek: Codable, Identifiable {
    var id: String { week }
    let week: String
    let ratio: Double
    let acute: Double
    let chronic: Double
}

// MARK: - Peak Prediction
struct PeakDay: Codable, Identifiable {
    var id: String { date }
    let date: String
    let predictedLss: Double
    let level: String    // "go" | "go_caution" | "reduce" | "defer"
    let isPeak: Bool

    enum CodingKeys: String, CodingKey {
        case date, level
        case predictedLss = "predicted_lss"
        case isPeak       = "is_peak"
    }
}

struct PeakPredictionResponse: Codable {
    let days: [PeakDay]
    let slope: Double
    let baseline: Double
}

// MARK: - Coach du jour
struct CoachTip: Codable {
    let title: String
    let body: String
    let domain: String  // "nutrition" | "training" | "recovery" | "sleep"
}

// MARK: - Morning Brief
struct MorningBriefData: Codable {
    let date: String
    let sessionToday: String
    let sessionIntensity: String
    let lss: Double?
    let recommendation: String  // "go" | "go_caution" | "reduce" | "defer"
    let message: String
    let adjustments: [String]
    let flags: MorningBriefFlags
    let dataCoverage: Double
    let components: MorningBriefComponents?
    // F4: ritual context for coaching
    let ritualRate7d: Double?
    let phoenixStreak: Int?

    enum CodingKeys: String, CodingKey {
        case date, lss, recommendation, message, adjustments, flags, components
        case sessionToday     = "session_today"
        case sessionIntensity = "session_intensity"
        case dataCoverage     = "data_coverage"
        case ritualRate7d     = "ritual_rate_7d"
        case phoenixStreak    = "phoenix_streak"
    }
}

struct MorningBriefFlags: Codable {
    let hrvDrop: Bool
    let sleepDeprivation: Bool
    let trainingOverload: Bool

    enum CodingKeys: String, CodingKey {
        case hrvDrop          = "hrv_drop"
        case sleepDeprivation = "sleep_deprivation"
        case trainingOverload = "training_overload"
    }
}

struct MorningBriefComponents: Codable {
    let sleepQuality: Double?
    let hrvTrend: Double?
    let rhrTrend: Double?
    let subjectiveStress: Double?
    let trainingFatigue: Double?

    enum CodingKeys: String, CodingKey {
        case sleepQuality     = "sleep_quality"
        case hrvTrend         = "hrv_trend"
        case rhrTrend         = "rhr_trend"
        case subjectiveStress = "subjective_stress"
        case trainingFatigue  = "training_fatigue"
    }
}

// MARK: - Cross-Correlation Insights
struct CorrelationInsight: Codable, Identifiable {
    var id: String { insightId }
    let insightId:      String
    let label:          String
    let insightDesc:    String
    let correlation:    Double
    let strength:       String
    let xVar:           String
    let yVar:           String
    let nPoints:        Int
    let icon:           String
    let color:          String

    enum CodingKeys: String, CodingKey {
        case label, correlation, strength, icon, color
        case insightId   = "id"
        case insightDesc = "description"
        case xVar        = "x_var"
        case yVar        = "y_var"
        case nPoints     = "n_points"
    }
}

struct CorrelationsData: Codable {
    let periodDays: Int
    let dataPoints: Int
    let computedAt: String
    let insights:   [CorrelationInsight]

    enum CodingKeys: String, CodingKey {
        case insights
        case periodDays = "period_days"
        case dataPoints = "data_points"
        case computedAt = "computed_at"
    }
}

// MARK: - Smart Day Recommendation
struct SmartDayRecommendation: Codable {
    let intensity:        String          // "normale" | "réduite" | "repos"
    let confidence:       Double          // 0–1
    let reason:           String
    let cta:              String
    let recoveryScore:    Double?
    let hrv:              Double?
    let restingHr:        Double?
    let acwr:             Double?
    let daysSinceSession: Int
    let suggestedSession: String?

    enum CodingKeys: String, CodingKey {
        case intensity, confidence, reason, cta, hrv, acwr
        case recoveryScore    = "recovery_score"
        case restingHr        = "resting_hr"
        case daysSinceSession = "days_since_session"
        case suggestedSession = "suggested_session"
    }

    var intensityColor: String {
        switch intensity {
        case "normale": return "green"
        case "réduite": return "orange"
        default:        return "red"
        }
    }
}

// MARK: - Weekly Report
struct WeeklyReport: Codable {
    let weekStart:           String
    let weekEnd:             String
    let sessionCount:        Int
    let totalVolumeLbs:      Double
    let prCount:             Int
    let topExercise:         String?
    let avgRecoveryScore:    Double?
    let avgSleepHours:       Double?
    let avgSteps:            Int?
    let avgHrv:              Double?
    let nutritionCompliance: Int?
    let avgRpe:              Double?
    let weeklyScore:         Int?
    let prs:                 [String]
    let focusNextWeek:       [String]
    let pushPullRatio:       WeeklyReportPushPull?

    enum CodingKeys: String, CodingKey {
        case weekStart           = "week_start"
        case weekEnd             = "week_end"
        case sessionCount        = "session_count"
        case totalVolumeLbs      = "total_volume_lbs"
        case prCount             = "pr_count"
        case topExercise         = "top_exercise"
        case avgRecoveryScore    = "avg_recovery_score"
        case avgSleepHours       = "avg_sleep_hours"
        case avgSteps            = "avg_steps"
        case avgHrv              = "avg_hrv"
        case nutritionCompliance = "nutrition_compliance"
        case avgRpe              = "avg_rpe"
        case weeklyScore         = "weekly_score"
        case prs
        case focusNextWeek       = "focus_next_week"
        case pushPullRatio       = "push_pull_ratio"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weekStart           = (try? c.decode(String.self, forKey: .weekStart)) ?? ""
        weekEnd             = (try? c.decode(String.self, forKey: .weekEnd)) ?? ""
        sessionCount        = (try? c.decode(Int.self, forKey: .sessionCount)) ?? 0
        totalVolumeLbs      = (try? c.decode(Double.self, forKey: .totalVolumeLbs)) ?? 0
        prCount             = (try? c.decode(Int.self, forKey: .prCount)) ?? 0
        topExercise         = try? c.decode(String.self, forKey: .topExercise)
        avgRecoveryScore    = try? c.decode(Double.self, forKey: .avgRecoveryScore)
        avgSleepHours       = try? c.decode(Double.self, forKey: .avgSleepHours)
        avgSteps            = try? c.decode(Int.self, forKey: .avgSteps)
        avgHrv              = try? c.decode(Double.self, forKey: .avgHrv)
        nutritionCompliance = try? c.decode(Int.self, forKey: .nutritionCompliance)
        avgRpe              = try? c.decode(Double.self, forKey: .avgRpe)
        weeklyScore         = try? c.decode(Int.self, forKey: .weeklyScore)
        prs                 = (try? c.decode([String].self, forKey: .prs)) ?? []
        focusNextWeek       = (try? c.decode([String].self, forKey: .focusNextWeek)) ?? []
        pushPullRatio       = try? c.decode(WeeklyReportPushPull.self, forKey: .pushPullRatio)
    }
}

// MARK: - Stats Expansion Analytics Models

struct ComplianceWeek: Codable, Identifiable {
    var id: String { weekStart }
    let weekStart: String
    let planned: Int
    let done: Int
    var rate: Double { planned > 0 ? Double(done) / Double(planned) : 0 }

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
        case planned, done
    }
}

struct RPEProgressionData: Codable {
    let lt7:  Double?
    let r7_8: Double?
    let r8_9: Double?
    let r9_10: Double?

    enum CodingKeys: String, CodingKey {
        case lt7   = "<7"
        case r7_8  = "7-8"
        case r8_9  = "8-9"
        case r9_10 = "9-10"
    }
}

struct RIREntry: Codable, Identifiable {
    var id: String { exercise }
    let exercise: String
    let avgRir: Double
    let nSets: Int

    enum CodingKeys: String, CodingKey {
        case exercise
        case avgRir = "avg_rir"
        case nSets  = "n_sets"
    }
}

// MARK: - Readiness Score
struct ReadinessScore: Codable {
    let score: Double?
    let label: String
    let color: String
    let components: [String: Double]?
    let hrvBaseline: Double?
    let dataSources: [String]

    enum CodingKeys: String, CodingKey {
        case score, label, color, components
        case hrvBaseline  = "hrv_baseline"
        case dataSources  = "data_sources"
    }
}

// MARK: - Push/Pull Ratio
struct PushPullRatio: Codable {
    let pushVolume: Double
    let pullVolume: Double
    let legsVolume: Double
    let ratio: Double?
    let imbalance: String?   // "push_dominant" | "pull_dominant" | nil

    enum CodingKeys: String, CodingKey {
        case ratio, imbalance
        case pushVolume  = "push_volume"
        case pullVolume  = "pull_volume"
        case legsVolume  = "legs_volume"
    }
}

// MARK: - Body Projection
struct BodyProjectionData: Codable {
    let bodyFat:   LinearReg?
    let leanMass:  LinearReg?
    let bodyWeight: LinearReg?
    let projections: [BodyGoalProjection]
    let bfSeries:   [BodyDataPoint]
    let leanSeries: [BodyDataPoint]

    enum CodingKeys: String, CodingKey {
        case projections
        case bodyFat    = "body_fat"
        case leanMass   = "lean_mass"
        case bodyWeight = "body_weight"
        case bfSeries   = "bf_series"
        case leanSeries = "lean_series"
    }
}

struct LinearReg: Codable {
    let slopePerDay:    Double
    let currentValue:   Double
    let r2:             Double?

    enum CodingKeys: String, CodingKey {
        case r2
        case slopePerDay  = "slope_per_day"
        case currentValue = "current_value"
    }
}

struct BodyGoalProjection: Codable, Identifiable {
    var id: String { goalType }
    let goalType:       String
    let target:         Double
    let current:        Double
    let slopePerWeek:   Double
    let r2:             Double?
    let projectedDate:  String?

    enum CodingKeys: String, CodingKey {
        case target, current, r2
        case goalType      = "goal_type"
        case slopePerWeek  = "slope_per_week"
        case projectedDate = "projected_date"
    }
}

struct BodyDataPoint: Codable, Identifiable {
    var id: String { date }
    let date:  String
    let value: Double
}

// MARK: - Pain Journal
struct PainJournalEntry: Codable, Identifiable {
    var id: String { (date ?? "") + (exercise ?? "") }
    let date:        String?
    let sessionName: String?
    let exercise:    String?
    let painZone:    String?
    let weight:      Double?
    let reps:        String?

    enum CodingKeys: String, CodingKey {
        case date, exercise, weight, reps
        case sessionName = "session_name"
        case painZone    = "pain_zone"
    }
}

struct PainExerciseSummary: Codable, Identifiable {
    var id: String { exercise }
    let exercise:  String
    let count:     Int
    let zones:     [String]
    let lastDate:  String?

    enum CodingKeys: String, CodingKey {
        case exercise, count, zones
        case lastDate = "last_date"
    }
}

struct PainJournalResponse: Codable {
    let entries:    [PainJournalEntry]
    let byExercise: [PainExerciseSummary]

    enum CodingKeys: String, CodingKey {
        case entries
        case byExercise = "by_exercise"
    }
}

// MARK: - Overtraining Risk
struct OvertrainingRisk: Codable {
    let riskScore:      Int
    let level:          String   // "low" | "moderate" | "high"
    let flags:          [String]
    let recommendation: String

    enum CodingKeys: String, CodingKey {
        case level, flags, recommendation
        case riskScore = "risk_score"
    }
}

// MARK: - Mesocycle Status
struct MesocycleStatus: Codable {
    let currentWeek:       Int
    let weekInCycle:       Int
    let weeksSinceDeload:  Int
    let phase:             String
    let phaseLabel:        String
    let description:       String
    let icon:              String
    let rpeTarget:         String
    let volGuidance:       String
    let lastDeloadDate:    String?
    let nextDeloadInWeeks: Int

    enum CodingKeys: String, CodingKey {
        case phase, description, icon
        case currentWeek      = "current_week"
        case weekInCycle      = "week_in_cycle"
        case weeksSinceDeload = "weeks_since_deload"
        case phaseLabel       = "phase_label"
        case rpeTarget        = "rpe_target"
        case volGuidance      = "vol_guidance"
        case lastDeloadDate   = "last_deload_date"
        case nextDeloadInWeeks = "next_deload_in_weeks"
    }
}

// MARK: - 1RM Programming
struct OneRMExercise: Codable, Identifiable {
    var id: String { exercise }
    let exercise:      String
    let estimated1rm:  Double
    let currentWeight: Double?
    let pctOf1rm:      Double?
    let table:         [OneRMTableEntry]

    enum CodingKeys: String, CodingKey {
        case exercise, table
        case estimated1rm  = "estimated_1rm"
        case currentWeight = "current_weight"
        case pctOf1rm      = "pct_of_1rm"
    }
}

struct OneRMTableEntry: Codable, Identifiable {
    var id: Int { pct }
    let pct:    Int
    let weight: Double
}

struct OneRMResponse: Codable {
    let exercises: [OneRMExercise]
}

// MARK: - Macro Gap
struct MacroGap: Codable {
    let date:        String
    let targets:     MacroValues
    let actual:      MacroValues
    let gaps:        MacroValues
    let primaryGap:  String
    let foodSuggestions:    [[String: SafeString]]
    let templateSuggestions: [[String: SafeString]]

    enum CodingKeys: String, CodingKey {
        case date, targets, actual, gaps
        case primaryGap          = "primary_gap"
        case foodSuggestions     = "food_suggestions"
        case templateSuggestions = "template_suggestions"
    }
}

struct MacroValues: Codable {
    let calories: Double
    let protein:  Double
    let carbs:    Double
    let fat:      Double
}

// MARK: - HRV Analysis (professional-grade)
struct HRVDataPoint: Codable, Identifiable {
    let date: String
    let hrv:  Double
    var id: String { date }
}

struct HRVAnalysis: Codable {
    let todayRmssd:         Double?
    let hrv7dAvg:           Double?
    let hrv30dAvg:          Double?
    let hrvCv:              Double?
    let hrvScore:           Double?
    let hrvZone:            String?
    let hrvTrend:           String?
    let consecutiveLowDays: Int
    let streakAlert:        Bool
    let contextualMessage:  String?
    let history7d:          [HRVDataPoint]
    let baselineAvailable:  Bool
    let dataPoints7d:       Int
    let dataPoints30d:      Int
    let sd30d:              Double?

    enum CodingKeys: String, CodingKey {
        case todayRmssd         = "today_rmssd"
        case hrv7dAvg           = "hrv_7d_avg"
        case hrv30dAvg          = "hrv_30d_avg"
        case hrvCv              = "hrv_cv"
        case hrvScore           = "hrv_score"
        case hrvZone            = "hrv_zone"
        case hrvTrend           = "hrv_trend"
        case consecutiveLowDays = "consecutive_low_days"
        case streakAlert        = "streak_alert"
        case contextualMessage  = "contextual_message"
        case history7d          = "history_7d"
        case baselineAvailable  = "baseline_available"
        case dataPoints7d       = "data_points_7d"
        case dataPoints30d      = "data_points_30d"
        case sd30d              = "sd_30d"
    }

    var zoneColor: Color {
        switch hrvZone {
        case "green":  return .statusGreen
        case "orange": return .statusOrange
        case "red":    return .statusRed
        default:       return .gray
        }
    }

    var trendArrow: String {
        switch hrvTrend {
        case "up":   return "↑"
        case "down": return "↓"
        default:     return "→"
        }
    }

    var trendColor: Color {
        switch hrvTrend {
        case "up":   return .statusGreen
        case "down": return .statusRed
        default:     return .gray
        }
    }

    var flagRest: Bool {
        guard let today = todayRmssd, let avg = hrv30dAvg, let sd = sd30d else { return false }
        return today < avg - sd
    }
    var deviationFrom30d: Double? {
        guard let today = todayRmssd, let avg = hrv30dAvg else { return nil }
        return round((today - avg) * 10) / 10
    }
}

// MARK: - Soreness Threshold
struct SorenessThreshold: Codable {
    let medianVolume:          Double?
    let avgSorenessLowVol:     Double?
    let avgSorenessHighVol:    Double?
    let thresholdVol:          Double?
    let message:               String?

    enum CodingKeys: String, CodingKey {
        case message
        case medianVolume       = "median_volume"
        case avgSorenessLowVol  = "avg_soreness_low_vol"
        case avgSorenessHighVol = "avg_soreness_high_vol"
        case thresholdVol       = "threshold_vol"
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

// MARK: - WeeklyReport extension
struct WeeklyReportPushPull: Codable {
    let pushVolume: Double
    let pullVolume: Double
    let legsVolume: Double
    let ratio:      Double?
    let imbalance:  String?

    enum CodingKeys: String, CodingKey {
        case ratio, imbalance
        case pushVolume = "push_volume"
        case pullVolume = "pull_volume"
        case legsVolume = "legs_volume"
    }
}
