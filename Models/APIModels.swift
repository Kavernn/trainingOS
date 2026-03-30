import Foundation
import SwiftUI

// MARK: - Pagination
struct PagedResponse<T: Codable>: Codable {
    let items: [T]
    let offset: Int
    let limit: Int
    let total: Int
    let hasMore: Bool
    let nextOffset: Int?
    enum CodingKeys: String, CodingKey {
        case items, offset, limit, total
        case hasMore    = "has_more"
        case nextOffset = "next_offset"
    }
}

struct SafeString: Codable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // 1. Tente de décoder une String
        if let str = try? container.decode(String.self) {
            self.value = str
        }
        // 2. Tente de décoder un tableau de Strings (tes fameux blocks)
        else if let arr = try? container.decode([String].self) {
            self.value = arr.joined(separator: ", ")
        }
        // 3. Tente de décoder un Int ou Double (au cas où)
        else if let num = try? container.decode(Double.self) {
            self.value = String(num)
        }
        // 4. Si c'est null ou autre chose, on ne crash pas !
        else {
            self.value = ""
        }
    }
    
    // Pour faciliter l'encodage vers Supabase si besoin
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}


// MARK: - Log Exercise Response
struct LogExerciseResponse: Codable {
    let success: Bool?
    let newWeight: Double?
    let oneRM: Double?
    let isPR: Bool?

    enum CodingKeys: String, CodingKey {
        case success
        case newWeight = "new_weight"
        case oneRM     = "1rm"
        case isPR      = "is_pr"
    }
}

// MARK: - Dashboard
struct DashboardData: Codable {
    let today: String
    let week: Int
    let todayDate: String

    let alreadyLoggedToday: Bool
    let hasPartialLogs: Bool
    let completed: Bool
    let schedule: [String: String]
    let sessions: [String: SessionEntry]
    let goals: [String: GoalProgress]
    let fullProgram: [String: [String: SafeString]]
    let nutritionTotals: NutritionTotals
    let nutritionSettings: NutritionSettings?
    let profile: UserProfile

    enum CodingKeys: String, CodingKey {
        case today, week
        case todayDate = "today_date"
        case alreadyLoggedToday = "already_logged_today"
        case hasPartialLogs = "has_partial_logs"
        case completed
        case schedule, sessions, goals
        case fullProgram = "full_program"
        case nutritionTotals = "nutrition_totals"
        case nutritionSettings = "nutrition_settings"
        case profile
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        today               = try c.decode(String.self, forKey: .today)
        week                = try c.decode(Int.self, forKey: .week)
        todayDate           = try c.decode(String.self, forKey: .todayDate)
        alreadyLoggedToday  = (try? c.decode(Bool.self, forKey: .alreadyLoggedToday)) ?? false
        hasPartialLogs      = (try? c.decode(Bool.self, forKey: .hasPartialLogs)) ?? false
        completed           = (try? c.decode(Bool.self, forKey: .completed)) ?? false
        schedule            = try c.decode([String: String].self, forKey: .schedule)
        sessions            = try c.decode([String: SessionEntry].self, forKey: .sessions)
        goals               = try c.decode([String: GoalProgress].self, forKey: .goals)
        fullProgram         = try c.decode([String: [String: SafeString]].self, forKey: .fullProgram)
        nutritionTotals     = try c.decode(NutritionTotals.self, forKey: .nutritionTotals)
        nutritionSettings   = try? c.decode(NutritionSettings.self, forKey: .nutritionSettings)
        profile             = try c.decode(UserProfile.self, forKey: .profile)
    }
}

struct SessionEntry: Codable {
    let exos: [String]?
    let rpe: Double?
    let comment: String?
    let loggedAt: String?
    let durationMin: Double?
    let energyPre: Int?
    let sessionVolume: Double?
    let totalReps: Int?
    let totalSets: Int?

    enum CodingKeys: String, CodingKey {
        case exos, rpe, comment
        case loggedAt      = "logged_at"
        case durationMin   = "duration_min"
        case energyPre     = "energy_pre"
        case sessionVolume = "session_volume"
        case totalReps     = "total_reps"
        case totalSets     = "total_sets"
    }
}

struct GoalProgress: Codable {
    let current: Double
    let goal: Double
    let achieved: Bool
}

struct NutritionTotals: Codable {
    let calories: Double?
    let proteines: Double?
    let glucides: Double?
    let lipides: Double?
}

struct UserProfile: Codable {
    let name: String?
    let weight: Double?
    let height: Double?
    let age: Int?
    let goal: String?
    let level: String?
    let sex: String?
    let photoB64: String?

    enum CodingKeys: String, CodingKey {
        case name, weight, height, age, goal, level, sex
        case photoB64 = "photo_b64"
    }
}

// MARK: - Exercise Prescription
struct ExercisePrescription: Codable {
    let sets: Int
    let repMin: Int
    let repMax: Int
    let note: String?

    enum CodingKeys: String, CodingKey {
        case sets, note
        case repMin = "rep_min"
        case repMax = "rep_max"
    }

    var label: String { "\(sets)×\(repMin)–\(repMax)" }
}

// MARK: - Muscle Landmark
struct MuscleLandmark: Codable {
    let mev: Int        // Minimum Effective Volume (weekly sets)
    let mav: Int        // Maximum Adaptive Volume
    let mrv: Int        // Maximum Recoverable Volume
    let weeklySets: Int // Actual sets logged this week

    enum CodingKeys: String, CodingKey {
        case mev, mav, mrv
        case weeklySets = "weekly_sets"
    }

    enum Zone { case underMEV, optimal, approachingMRV, overMRV }

    var zone: Zone {
        if weeklySets < mev  { return .underMEV }
        if weeklySets > mrv  { return .overMRV }
        if weeklySets >= mav { return .approachingMRV }
        return .optimal
    }
}

// MARK: - Programs
struct ProgramInfo: Codable, Identifiable, Equatable {
    let id: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case id, name
    }
}

// MARK: - Seance
struct SeanceData: Codable {
    let today: String
    let todayDate: String
    let alreadyLogged: Bool

    let schedule: [String: String]
    let fullProgram: [String: [String: SafeString]]
    let weights: [String: WeightData]
    let week: Int
    let inventoryTypes: [String: String]
    let inventoryTracking: [String: String]   // "reps" | "time"
    let inventoryRest: [String: Int]          // exercise name → rest seconds
    let exerciseOrder: [String: [String]]
    let prescriptions: [String: ExercisePrescription]?

    enum CodingKeys: String, CodingKey {
        case today
        case todayDate = "today_date"
        case alreadyLogged = "already_logged"
        case schedule
        case fullProgram = "full_program"
        case weights, week, prescriptions
        case inventoryTypes    = "inventory_types"
        case inventoryTracking = "inventory_tracking"
        case inventoryRest     = "inventory_rest"
        case exerciseOrder     = "exercise_order"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        today              = try c.decode(String.self, forKey: .today)
        todayDate          = try c.decode(String.self, forKey: .todayDate)
        alreadyLogged      = try c.decode(Bool.self, forKey: .alreadyLogged)
        schedule           = try c.decode([String: String].self, forKey: .schedule)
        fullProgram        = try c.decode([String: [String: SafeString]].self, forKey: .fullProgram)
        weights            = try c.decode([String: WeightData].self, forKey: .weights)
        week               = try c.decode(Int.self, forKey: .week)
        inventoryTypes     = (try? c.decode([String: String].self, forKey: .inventoryTypes))    ?? [:]
        inventoryTracking  = (try? c.decode([String: String].self, forKey: .inventoryTracking)) ?? [:]
        inventoryRest      = (try? c.decode([String: Int].self,    forKey: .inventoryRest))     ?? [:]
        exerciseOrder      = (try? c.decode([String: [String]].self, forKey: .exerciseOrder))   ?? [:]
        prescriptions      = try? c.decode([String: ExercisePrescription].self, forKey: .prescriptions)
    }

    init(today: String, todayDate: String, alreadyLogged: Bool,
         schedule: [String: String], fullProgram: [String: [String: SafeString]],
         weights: [String: WeightData], week: Int,
         inventoryTypes: [String: String], inventoryTracking: [String: String] = [:],
         inventoryRest: [String: Int] = [:],
         exerciseOrder: [String: [String]],
         prescriptions: [String: ExercisePrescription]? = nil) {
        self.today              = today
        self.todayDate          = todayDate
        self.alreadyLogged      = alreadyLogged
        self.schedule           = schedule
        self.fullProgram        = fullProgram
        self.weights            = weights
        self.week               = week
        self.inventoryTypes     = inventoryTypes
        self.inventoryTracking  = inventoryTracking
        self.inventoryRest      = inventoryRest
        self.exerciseOrder      = exerciseOrder
        self.prescriptions      = prescriptions
    }
}

struct SeanceSoirData: Codable {
    let hasEveningSession: Bool
    let todaySoir: String?
    let todayDate: String
    let alreadyLogged: Bool
    let schedule: [String: String]
    let fullProgram: [String: [String: SafeString]]
    let weights: [String: WeightData]
    let week: Int
    let inventoryTypes: [String: String]
    let inventoryTracking: [String: String]
    let inventoryRest: [String: Int]
    let exerciseOrder: [String: [String]]

    enum CodingKeys: String, CodingKey {
        case hasEveningSession = "has_evening_session"
        case todaySoir         = "today_soir"
        case todayDate         = "today_date"
        case alreadyLogged     = "already_logged"
        case schedule
        case fullProgram       = "full_program"
        case weights, week
        case inventoryTypes    = "inventory_types"
        case inventoryTracking = "inventory_tracking"
        case inventoryRest     = "inventory_rest"
        case exerciseOrder     = "exercise_order"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hasEveningSession = (try? c.decode(Bool.self,               forKey: .hasEveningSession)) ?? false
        todaySoir         =  try? c.decode(String.self,             forKey: .todaySoir)
        todayDate         = (try? c.decode(String.self,             forKey: .todayDate))         ?? ""
        alreadyLogged     = (try? c.decode(Bool.self,               forKey: .alreadyLogged))     ?? false
        schedule          = (try? c.decode([String: String].self,   forKey: .schedule))          ?? [:]
        fullProgram       = (try? c.decode([String: [String: SafeString]].self, forKey: .fullProgram)) ?? [:]
        weights           = (try? c.decode([String: WeightData].self, forKey: .weights))         ?? [:]
        week              = (try? c.decode(Int.self,                forKey: .week))              ?? 0
        inventoryTypes    = (try? c.decode([String: String].self,   forKey: .inventoryTypes))    ?? [:]
        inventoryTracking = (try? c.decode([String: String].self,   forKey: .inventoryTracking)) ?? [:]
        inventoryRest     = (try? c.decode([String: Int].self,      forKey: .inventoryRest))     ?? [:]
        exerciseOrder     = (try? c.decode([String: [String]].self, forKey: .exerciseOrder))     ?? [:]
    }

    func asSeanceData() -> SeanceData? {
        guard let soir = todaySoir else { return nil }
        return SeanceData(today: soir, todayDate: todayDate, alreadyLogged: alreadyLogged,
                         schedule: schedule, fullProgram: fullProgram, weights: weights,
                         week: week, inventoryTypes: inventoryTypes, inventoryTracking: inventoryTracking,
                         inventoryRest: inventoryRest, exerciseOrder: exerciseOrder)
    }
}

struct WeightData: Codable {
    let currentWeight: Double?
    let lastReps: String?
    let lastLogged: String?
    let history: [WeightHistoryEntry]?

    enum CodingKeys: String, CodingKey {
        case currentWeight = "current_weight"
        case lastReps = "last_reps"
        case lastLogged = "last_logged"
        case history
    }
}

struct WeightHistoryEntry: Codable {
    let date: String?
    let weight: Double?         // average weight across sets
    let reps: String?
    let note: String?
    let oneRM: Double?
    let sets: [SetEntry]?       // raw per-set data
    let exerciseVolume: Double? // total volume for this exercise entry

    struct SetEntry: Codable {
        let weight: Double
        let reps: String
        let totalWeight: Double?
        let setVolume: Double?
        let rir: Int?

        enum CodingKeys: String, CodingKey {
            case weight, reps, rir
            case totalWeight = "total_weight"
            case setVolume   = "set_volume"
        }
    }

    enum CodingKeys: String, CodingKey {
        case date, weight, reps, note, sets
        case oneRM          = "1rm"
        case exerciseVolume = "exercise_volume"
    }
}

// MARK: - HIIT
struct HIITEntry: Codable, Identifiable {
    var id: String { (date ?? "") + (sessionType ?? "") }
    let date: String?
    let sessionType: String?
    let rounds: Int?
    let workTime: Int?
    let restTime: Int?
    let rpe: Double?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case date, rounds, rpe, notes
        case sessionType = "session_type"
        case workTime = "work_time"
        case restTime = "rest_time"
    }
}

// MARK: - Muscle Stats
struct MuscleStatEntry: Codable {
    let volume: Double
    let sessions: Int
    let lastDate: String

    enum CodingKeys: String, CodingKey {
        case volume, sessions
        case lastDate = "last_date"
    }
}

// MARK: - Body Weight
struct BodyWeightEntry: Codable, Identifiable {
    var id: String { date }
    let date: String
    let weight: Double
    let bodyFat: Double?
    let waistCm: Double?
    let armsCm: Double?
    let chestCm: Double?
    let thighsCm: Double?
    let hipsCm: Double?

    enum CodingKeys: String, CodingKey {
        case date
        case weight   = "poids"
        case bodyFat  = "body_fat"
        case waistCm  = "waist_cm"
        case armsCm   = "arms_cm"
        case chestCm  = "chest_cm"
        case thighsCm = "thighs_cm"
        case hipsCm   = "hips_cm"
    }
}

// MARK: - Cardio
struct CardioEntry: Codable, Identifiable {
    var id: String { (date ?? "") + (type ?? "") }
    let date: String?
    let type: String?
    let durationMin: Double?
    let distanceKm: Double?
    let avgPace: String?
    let avgHr: Double?
    let cadence: Double?
    let calories: Double?
    let rpe: Double?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case date, type, rpe, notes, cadence, calories
        case durationMin = "duration_min"
        case distanceKm  = "distance_km"
        case avgPace     = "avg_pace"
        case avgHr       = "avg_hr"
    }
}

// MARK: - Recovery
struct RecoveryEntry: Codable, Identifiable {
    var id: String { date ?? "" }
    let date: String?
    let sleepHours: Double?
    let sleepQuality: Double?
    let restingHr: Double?
    let hrv: Double?
    let steps: Int?
    let soreness: Double?
    let activeEnergy: Double?
    let source: String?         // "manual" | "healthkit"
    let notes: String?

    var isFromWatch: Bool { source == "healthkit" }

    enum CodingKeys: String, CodingKey {
        case date, hrv, steps, soreness, notes, source
        case sleepHours   = "sleep_hours"
        case sleepQuality = "sleep_quality"
        case restingHr    = "resting_hr"
        case activeEnergy = "active_energy"
    }
}

// MARK: - Wearable Snapshot (Apple Watch → Supabase)
struct WearableWorkout {
    let type: String
    let durationMin: Double
    let distanceKm: Double?
    let calories: Double?
    let avgHr: Double?
    let avgPace: String?
}

struct WearableSnapshot {
    let date: String
    let steps: Int?
    let sleepHours: Double?
    let restingHr: Double?
    let hrv: Double?
    let activeEnergy: Double?
    let bodyWeightLbs: Double?
    let bodyFatPct: Double?
    let workouts: [WearableWorkout]
}

// MARK: - Objectifs
struct ObjectifEntry: Identifiable {
    var id: String { exercise }
    let exercise: String
    let current: Double
    let goal: Double
    let achieved: Bool
    let deadline: String
    let note: String
    var archived: Bool = false
}

// MARK: - Nutrition
struct NutritionEntry: Codable, Identifiable {
    var id: String { entryId ?? (name ?? "") + "\(calories ?? 0)" }
    let entryId: String?
    let name: String?
    let calories: Double?
    let proteines: Double?
    let glucides: Double?
    let lipides: Double?
    let quantity: Double?
    let unit: String?
    let time: String?
    let mealType: String?
}

struct NutritionSettings: Codable {
    let calories: Double?
    let proteines: Double?
    let glucides: Double?
    let lipides: Double?

    init(calories: Double?, proteines: Double?, glucides: Double?, lipides: Double?) {
        self.calories = calories; self.proteines = proteines
        self.glucides = glucides; self.lipides = lipides
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        calories  = (try? c.decode(Double.self, forKey: .init("limite_calories")))
                 ?? (try? c.decode(Double.self, forKey: .init("calories")))
        proteines = (try? c.decode(Double.self, forKey: .init("objectif_proteines")))
                 ?? (try? c.decode(Double.self, forKey: .init("proteines")))
        glucides  = try? c.decode(Double.self, forKey: .init("glucides"))
        lipides   = try? c.decode(Double.self, forKey: .init("lipides"))
    }
}

private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

// MARK: - Historique
struct HistoriqueSession: Identifiable {
    let id: String
    let date: String
    let entry: SessionEntry
}

// MARK: - Nutrition Day (for stats compliance chart)
struct NutritionDay: Codable, Identifiable {
    var id: String { date ?? "" }
    let date: String?
    let calories: Double?
    let proteines: Double?
    let glucides: Double?
    let lipides: Double?
}

// MARK: - Health Dashboard
struct DailyHealthSummary: Codable, Identifiable {
    var id: String { date }
    let date: String

    // Capteurs / récupération
    let steps: Int?
    let sleepDuration: Double?
    let sleepQuality: Double?
    let restingHeartRate: Double?
    let hrv: Double?
    let soreness: Double?
    let recoveryScore: Double?
    let heartRateAvg: Double?

    // Composition corporelle
    let bodyWeight: Double?
    let bodyFatPct: Double?
    let waistCm: Double?

    // Cardio
    let distanceKm: Double?
    let activeMinutes: Double?
    let pace: String?
    let cardioType: String?
    let cardioCalories: Double?

    // Musculation
    let trainingRpe: Double?
    let trainingDurationMin: Double?
    let trainingEnergyPre: Int?
    let trainingExercises: [String]?

    // Nutrition
    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let meals: Int?

    // Méta
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

// MARK: - Life Stress Engine

struct LifeStressComponents: Codable {
    let sleepQuality: Double?
    let hrvTrend: Double?
    let rhrTrend: Double?
    let subjectiveStress: Double?
    let trainingFatigue: Double?

    enum CodingKeys: String, CodingKey {
        case sleepQuality    = "sleep_quality"
        case hrvTrend        = "hrv_trend"
        case rhrTrend        = "rhr_trend"
        case subjectiveStress = "subjective_stress"
        case trainingFatigue = "training_fatigue"
    }
}

struct LifeStressFlags: Codable {
    let hrvDrop: Bool
    let sleepDeprivation: Bool
    let trainingOverload: Bool

    enum CodingKeys: String, CodingKey {
        case hrvDrop         = "hrv_drop"
        case sleepDeprivation = "sleep_deprivation"
        case trainingOverload = "training_overload"
    }
}

struct LifeStressScore: Codable, Identifiable {
    var id: String { date }
    let date: String
    let score: Double
    let components: LifeStressComponents
    let flags: LifeStressFlags
    let recommendations: [String]
    let dataCoverage: Double

    enum CodingKeys: String, CodingKey {
        case date, score, components, flags, recommendations
        case dataCoverage = "data_coverage"
    }

    /// Couleur sémantique basée sur le score
    var scoreColor: String {
        switch score {
        case 80...: return "green"
        case 60..<80: return "yellow"
        case 40..<60: return "orange"
        default:      return "red"
        }
    }
}

// MARK: - PSS (Perceived Stress Scale)

struct PSSQuestion: Codable, Identifiable {
    let id: Int
    let text: String
    let positive: Bool
}

struct PSSRecord: Codable, Identifiable {
    var id: String
    let date: String
    let type: String            // "full" | "short"
    let responses: [Int]
    let score: Int
    let maxScore: Int
    let category: String        // "low" | "moderate" | "high"
    let categoryLabel: String
    let invertedResponses: [Int]
    let notes: String?
    let triggers: [String]
    let triggerRatings: [String: Int]
    let streak: Int
    let insights: [String]

    enum CodingKeys: String, CodingKey {
        case id, date, type, responses, score, category, notes, triggers, streak, insights
        case maxScore          = "max_score"
        case categoryLabel     = "category_label"
        case invertedResponses = "inverted_responses"
        case triggerRatings    = "trigger_ratings"
    }

    var categoryColor: Color {
        switch category {
        case "low":      return .green
        case "moderate": return .orange
        default:         return .red
        }
    }
}

struct PSSDueStatus: Codable {
    let isDue: Bool
    let daysSinceLast: Int?
    let nextDueDate: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case isDue         = "is_due"
        case daysSinceLast = "days_since_last"
        case nextDueDate   = "next_due_date"
        case message
    }
}

// MARK: - Exercise Log (Seance logging)
struct ExerciseLog: Codable, Identifiable {
    var id = UUID()
    let name: String
    var sets: [SetEntry]

    enum CodingKeys: String, CodingKey {
        case name, sets
    }
}

struct SetEntry: Codable, Identifiable {
    var id = UUID()
    var weight: Double
    var reps: Int

    enum CodingKeys: String, CodingKey {
        case weight, reps
    }
}

// MARK: - Santé Mentale

// — Mood —

struct MoodEmotion: Codable, Identifiable {
    let id: String
    let label: String
    let emoji: String
    let valence: Int
}

struct MoodEntry: Codable, Identifiable {
    let id: String
    let date: String
    let score: Int
    let emotions: [String]
    let notes: String?
    let triggers: [String]
    let pssScoreLinked: Int?

    enum CodingKeys: String, CodingKey {
        case id, date, score, emotions, notes, triggers
        case pssScoreLinked = "pss_score_linked"
    }
}

struct MoodDueStatus: Codable {
    let isDue: Bool
    let message: String?

    enum CodingKeys: String, CodingKey {
        case isDue    = "is_due"
        case message
    }
}

// — Journal —

struct JournalEntry: Codable, Identifiable {
    let id: String
    let date: String
    let prompt: String
    let content: String
}

// — Breathwork —

struct BreathworkPhase: Codable {
    let phase: String
    let label: String
    let seconds: Int
}

struct BreathworkTechnique: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let color: String
    let phases: [BreathworkPhase]
    let targetCycles: Int
    let totalSec: Int
    let difficulty: String

    enum CodingKeys: String, CodingKey {
        case id, name, description, icon, color, phases, difficulty
        case targetCycles = "target_cycles"
        case totalSec     = "total_sec"
    }
}

struct BreathworkSession: Codable, Identifiable {
    let id: String
    let date: String
    let techniqueId: String
    let technique: String
    let durationSec: Int
    let cycles: Int

    enum CodingKeys: String, CodingKey {
        case id, date, technique, cycles
        case techniqueId  = "technique_id"
        case durationSec  = "duration_sec"
    }
}

struct BreathworkStats: Codable {
    let sessionsCount: Int
    let totalMinutes: Int
    let favorite: String?
    let byTechnique: [String: Int]
    let days: Int

    enum CodingKeys: String, CodingKey {
        case favorite, days
        case sessionsCount = "sessions_count"
        case totalMinutes  = "total_minutes"
        case byTechnique   = "by_technique"
    }
}

// — Self-Care —

struct SelfCareHabit: Codable, Identifiable {
    let id: String
    let name: String
    let icon: String
    let category: String
    let isDefault: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, icon, category
        case isDefault = "is_default"
    }
}

struct SelfCareToday: Codable {
    let date: String
    let habits: [SelfCareHabit]
    let completed: [String]
    let rate: Double
}

struct SelfCareStreak: Codable, Identifiable {
    var id: String { habitId }
    let habitId: String
    let habitName: String
    let habitIcon: String
    let currentStreak: Int
    let longestStreak: Int

    enum CodingKeys: String, CodingKey {
        case habitId      = "habit_id"
        case habitName    = "habit_name"
        case habitIcon    = "habit_icon"
        case currentStreak = "current_streak"
        case longestStreak = "longest_streak"
    }
}

// — Mental Health Dashboard —

struct MentalHealthSummary: Codable {
    let periodDays: Int
    let avgMood: Double?
    let moodTrend: String
    let moodHistory: [MoodEntry]
    let breathworkSessions: Int
    let breathworkMinutes: Int
    let journalEntries: Int
    let selfCareRate: Double
    let topStreaks: [SelfCareStreak]
    let topEmotions: [String]
    let insights: [String]
    let correlations: [String]
    let pssScore: Int?
    let pssCategory: String?

    enum CodingKeys: String, CodingKey {
        case insights, correlations
        case periodDays        = "period_days"
        case avgMood           = "avg_mood"
        case moodTrend         = "mood_trend"
        case moodHistory       = "mood_history"
        case breathworkSessions = "breathwork_sessions"
        case breathworkMinutes  = "breathwork_minutes"
        case journalEntries    = "journal_entries"
        case selfCareRate      = "self_care_rate"
        case topStreaks         = "top_streaks"
        case topEmotions       = "top_emotions"
        case pssScore          = "pss_score"
        case pssCategory       = "pss_category"
    }
}

// — Sommeil —

struct SleepEntry: Codable, Identifiable {
    let id: String
    let date: String
    let bedtime: String
    let wakeTime: String
    let durationHours: Double
    let quality: Int
    let qualityLabel: String
    let qualityEmoji: String
    let durationCategory: String
    let notes: String?
    let insights: [String]
    let loggedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, date, bedtime, notes, insights, quality
        case wakeTime         = "wake_time"
        case durationHours    = "duration_hours"
        case qualityLabel     = "quality_label"
        case qualityEmoji     = "quality_emoji"
        case durationCategory = "duration_category"
        case loggedAt         = "logged_at"
    }
}

struct SleepStats: Codable {
    let avgDuration: Double?
    let avgQuality: Double?
    let total: Int
    let streak: Int

    enum CodingKeys: String, CodingKey {
        case total, streak
        case avgDuration = "avg_duration"
        case avgQuality  = "avg_quality"
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

