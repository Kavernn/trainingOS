import Foundation

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
        stagnants    = try c.decodeIfPresent([String].self,       forKey: .stagnants)    ?? []
        fatigueRpe   = try c.decodeIfPresent(Bool.self,           forKey: .fatigueRpe)   ?? false
        recommande   = try c.decodeIfPresent(Bool.self,           forKey: .recommande)   ?? false
        poidsDeload  = try c.decodeIfPresent([String: Double].self, forKey: .poidsDeload) ?? [:]
        fatigueScore = try c.decodeIfPresent(Int.self,            forKey: .fatigueScore) ?? 0
        streakDays   = try c.decodeIfPresent(Int.self,            forKey: .streakDays)   ?? 0
        rpeAvg7j     = try c.decodeIfPresent(Double.self,         forKey: .rpeAvg7j)
    }

    /// 0 = OK, 1 = attention (score ≥ 65), 2 = critique (score ≥ 75 ou deload recommandé)
    var fatigueLevel: Int {
        if recommande || fatigueScore >= 75 { return 2 }
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
    let zone: ACWRZone
    let trend: [ACWRWeek]

    enum CodingKeys: String, CodingKey {
        case ratio, zone, trend
        case acuteLoad   = "acute_load"
        case chronicLoad = "chronic_load"
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

    enum CodingKeys: String, CodingKey {
        case date, lss, recommendation, message, adjustments, flags, components
        case sessionToday     = "session_today"
        case sessionIntensity = "session_intensity"
        case dataCoverage     = "data_coverage"
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
