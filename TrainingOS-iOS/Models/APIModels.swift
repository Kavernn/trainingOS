import Foundation

// MARK: - Dashboard

struct DashboardData: Codable {
    let today: String
    let week: Int
    let todayDate: String
    let alreadyLoggedToday: Bool
    let schedule: [String: String]
    let sessions: [String: SessionEntry]
    let suggestions: [String: SuggestionEntry]
    let goals: [String: GoalProgress]
    let fullProgram: [String: SessionTemplate]   // block-based
    let nutritionTotals: NutritionTotals
    let profile: UserProfile

    enum CodingKeys: String, CodingKey {
        case today, week
        case todayDate = "today_date"
        case alreadyLoggedToday = "already_logged_today"
        case schedule, sessions, suggestions, goals
        case fullProgram = "full_program"
        case nutritionTotals = "nutrition_totals"
        case profile
    }
}

// MARK: - Workout Blocks (program templates)

enum BlockType: String, Codable {
    case strength
    case hiit
    case cardio
}

struct WorkoutBlock: Codable, Identifiable {
    var id: String { "\(type.rawValue)-\(order)" }

    let type: BlockType
    let order: Int
    let exercises: [String: String]?    // strength only
    let hiitConfig: HIITConfig?         // hiit only
    let cardioConfig: CardioConfig?     // cardio only

    enum CodingKeys: String, CodingKey {
        case type, order, exercises
        case hiitConfig   = "hiit_config"
        case cardioConfig = "cardio_config"
    }
}

struct HIITConfig: Codable {
    let sprint: Int?
    let rest: Int?
    let rounds: Int?
    let speed: String?
}

struct CardioConfig: Codable {
    let targetMin: Int?
    let intensity: String?

    enum CodingKeys: String, CodingKey {
        case targetMin = "target_min"
        case intensity
    }
}

/// A session template as stored in the program (a container of blocks).
struct SessionTemplate: Codable {
    let blocks: [WorkoutBlock]

    /// Blocks sorted by their declared order.
    var sortedBlocks: [WorkoutBlock] { blocks.sorted { $0.order < $1.order } }

    /// Exercises from the strength block, sorted alphabetically.
    var strengthExercises: [(name: String, scheme: String)] {
        let dict = blocks.first(where: { $0.type == .strength })?.exercises ?? [:]
        return dict.map { ($0.key, $0.value) }.sorted { $0.name < $1.name }
    }
}

// MARK: - Logged Session

struct SessionEntry: Codable {
    let exos: [String]?          // legacy flat list (backward compat)
    let blocks: [LoggedBlock]?   // new block-based log
    let rpe: Double?
    let comment: String?
    let loggedAt: String?
    let durationMin: Int?
    let energyPre: Double?

    enum CodingKeys: String, CodingKey {
        case exos, blocks, rpe, comment
        case loggedAt    = "logged_at"
        case durationMin = "duration_min"
        case energyPre   = "energy_pre"
    }
}

/// A single modality block as recorded in a logged session.
struct LoggedBlock: Codable {
    let type: BlockType
    let order: Int
    // Strength
    let exos: [String]?
    // HIIT
    let rounds: Int?
    let speed: String?
    // Cardio
    let durationMin: Int?
    let distanceKm: Double?

    enum CodingKeys: String, CodingKey {
        case type, order, exos, rounds, speed
        case durationMin = "duration_min"
        case distanceKm  = "distance_km"
    }
}

// MARK: - Exercise Suggestions

struct SuggestionEntry: Codable {
    let weight: Double?
    let reps: String?
    let sets: String?
    let note: String?
}

// MARK: - Goals

struct GoalProgress: Codable {
    let current: Double
    let goal: Double
    let achieved: Bool
}

// MARK: - Nutrition

struct NutritionTotals: Codable {
    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
}

// MARK: - User Profile

struct UserProfile: Codable {
    let name: String?
    let weight: Double?
    let height: Double?
    let photoUrl: String?

    enum CodingKeys: String, CodingKey {
        case name, weight, height
        case photoUrl = "photo_url"
    }
}

// MARK: - Seance (live logging)

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

// MARK: - Historique

struct HistoriqueSession: Identifiable {
    let id: String   // date string as key
    let date: String
    let entry: SessionEntry
}
