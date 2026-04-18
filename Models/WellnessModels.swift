import Foundation

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

// MARK: - Mood
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

// MARK: - Journal
struct JournalEntry: Codable, Identifiable {
    let id: String
    let date: String
    let prompt: String
    let content: String
    let moodScore: Int?

    enum CodingKeys: String, CodingKey {
        case id, date, prompt, content
        case moodScore = "mood_score"
    }
}

// MARK: - Breathwork
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

// MARK: - Self-Care
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

// MARK: - Mental Health Summary
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

// MARK: - Sleep
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
