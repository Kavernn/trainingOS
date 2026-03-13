import Foundation
import SwiftUI

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


// MARK: - Dashboard
struct DashboardData: Codable {
    let today: String
    let week: Int
    let todayDate: String

    /// Séance calculée à partir du jour LOCAL de l'iPhone (fiable même si le serveur a un bug timezone).
    var localToday: String {
        // Calendar weekday: 1=dim, 2=lun, ..., 7=sam → on converti en 0=lun..6=dim
        let weekday = Calendar.current.component(.weekday, from: Date())
        let idx = (weekday + 5) % 7
        let schedule: [Int: String] = [
            0: "Upper A", 1: "HIIT 1", 2: "Upper B",
            3: "HIIT 2",  4: "Lower",  5: "Yoga",  6: "Recovery"
        ]
        return schedule[idx] ?? today
    }

    let alreadyLoggedToday: Bool
    let schedule: [String: String]
    let sessions: [String: SessionEntry]
    let goals: [String: GoalProgress]
    let fullProgram: [String: [String: SafeString]]
    let nutritionTotals: NutritionTotals
    let profile: UserProfile

    enum CodingKeys: String, CodingKey {
        case today, week
        case todayDate = "today_date"
        case alreadyLoggedToday = "already_logged_today"
        case schedule, sessions, goals
        case fullProgram = "full_program"
        case nutritionTotals = "nutrition_totals"
        case profile
    }
}

struct SessionEntry: Codable {
    let exos: [String]?
    let rpe: Double?
    let comment: String?
    let loggedAt: String?
    let durationMin: Double?
    let energyPre: Int?

    enum CodingKeys: String, CodingKey {
        case exos, rpe, comment
        case loggedAt    = "logged_at"
        case durationMin = "duration_min"
        case energyPre   = "energy_pre"
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

// MARK: - Seance
struct SeanceData: Codable {
    let today: String
    let todayDate: String
    let alreadyLogged: Bool

    var localToday: String {
        let weekday = Calendar.current.component(.weekday, from: Date())
        let idx = (weekday + 5) % 7
        let schedule: [Int: String] = [
            0: "Upper A", 1: "HIIT 1", 2: "Upper B",
            3: "HIIT 2",  4: "Lower",  5: "Yoga",  6: "Recovery"
        ]
        return schedule[idx] ?? today
    }

    let schedule: [String: String]
    let fullProgram: [String: [String: SafeString]]
    let weights: [String: WeightData]
    let week: Int

    enum CodingKeys: String, CodingKey {
        case today
        case todayDate = "today_date"
        case alreadyLogged = "already_logged"
        case schedule
        case fullProgram = "full_program"
        case weights, week
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
    let weight: Double?   // average weight across sets
    let reps: String?
    let note: String?
    let oneRM: Double?
    let sets: [SetEntry]? // raw per-set data (weight + reps per set)

    struct SetEntry: Codable {
        let weight: Double
        let reps: String
    }

    enum CodingKeys: String, CodingKey {
        case date, weight, reps, note, sets
        case oneRM = "1rm"
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
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case date, hrv, steps, soreness, notes
        case sleepHours   = "sleep_hours"
        case sleepQuality = "sleep_quality"
        case restingHr    = "resting_hr"
    }
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
}

struct NutritionSettings: Codable {
    let calories: Double?
    let proteines: Double?
    let glucides: Double?
    let lipides: Double?
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

// MARK: - Deload
struct DeloadReport: Codable {
    let deloadActif: Bool
    let stagnants: [String]
    let fatigueRpe: Bool
    let recommande: Bool
    let poidsDeload: [String: Double]

    enum CodingKeys: String, CodingKey {
        case deloadActif  = "deload_actif"
        case stagnants
        case fatigueRpe   = "fatigue_rpe"
        case recommande
        case poidsDeload  = "poids_deload"
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
