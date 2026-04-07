import Foundation

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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exos = try? c.decode([String].self, forKey: .exos)
        comment = try? c.decode(String.self, forKey: .comment)
        loggedAt = try? c.decode(String.self, forKey: .loggedAt)

        func decodeDouble(_ key: CodingKeys) -> Double? {
            if let v = try? c.decode(Double.self, forKey: key) { return v }
            if let v = try? c.decode(Int.self, forKey: key) { return Double(v) }
            if let s = try? c.decode(String.self, forKey: key) { return Double(s) }
            return nil
        }
        func decodeInt(_ key: CodingKeys) -> Int? {
            if let v = try? c.decode(Int.self, forKey: key) { return v }
            if let v = try? c.decode(Double.self, forKey: key) { return Int(v) }
            if let s = try? c.decode(String.self, forKey: key), let d = Double(s) { return Int(d) }
            return nil
        }

        rpe = decodeDouble(.rpe)
        durationMin = decodeDouble(.durationMin)
        sessionVolume = decodeDouble(.sessionVolume)
        energyPre = decodeInt(.energyPre)
        totalReps = decodeInt(.totalReps)
        totalSets = decodeInt(.totalSets)
    }
}

struct GoalProgress: Codable {
    let current: Double
    let goal: Double
    let achieved: Bool
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
    let exerciseSuggestions: [String: ProgressionSuggestion]?

    enum CodingKeys: String, CodingKey {
        case today
        case todayDate = "today_date"
        case alreadyLogged = "already_logged"
        case schedule
        case fullProgram = "full_program"
        case weights, week, prescriptions
        case inventoryTypes       = "inventory_types"
        case inventoryTracking    = "inventory_tracking"
        case inventoryRest        = "inventory_rest"
        case exerciseOrder        = "exercise_order"
        case exerciseSuggestions  = "exercise_suggestions"
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
        exerciseSuggestions = try? c.decode([String: ProgressionSuggestion].self, forKey: .exerciseSuggestions)
    }

    init(today: String, todayDate: String, alreadyLogged: Bool,
         schedule: [String: String], fullProgram: [String: [String: SafeString]],
         weights: [String: WeightData], week: Int,
         inventoryTypes: [String: String], inventoryTracking: [String: String] = [:],
         inventoryRest: [String: Int] = [:],
         exerciseOrder: [String: [String]],
         prescriptions: [String: ExercisePrescription]? = nil,
         exerciseSuggestions: [String: ProgressionSuggestion]? = nil) {
        self.today               = today
        self.todayDate           = todayDate
        self.alreadyLogged       = alreadyLogged
        self.schedule            = schedule
        self.fullProgram         = fullProgram
        self.weights             = weights
        self.week                = week
        self.inventoryTypes      = inventoryTypes
        self.inventoryTracking   = inventoryTracking
        self.inventoryRest       = inventoryRest
        self.exerciseOrder       = exerciseOrder
        self.prescriptions       = prescriptions
        self.exerciseSuggestions = exerciseSuggestions
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

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            weight = (try? c.decode(Double.self, forKey: .weight))
                ?? (try? c.decode(Int.self, forKey: .weight)).map(Double.init)
                ?? 0
            if let r = try? c.decode(String.self, forKey: .reps) {
                reps = r
            } else if let r = try? c.decode(Int.self, forKey: .reps) {
                reps = String(r)
            } else if let r = try? c.decode(Double.self, forKey: .reps) {
                reps = String(Int(r))
            } else {
                reps = ""
            }
            totalWeight = (try? c.decode(Double.self, forKey: .totalWeight))
                ?? (try? c.decode(Int.self, forKey: .totalWeight)).map(Double.init)
            setVolume = (try? c.decode(Double.self, forKey: .setVolume))
                ?? (try? c.decode(Int.self, forKey: .setVolume)).map(Double.init)
            rir = (try? c.decode(Int.self, forKey: .rir))
                ?? (try? c.decode(Double.self, forKey: .rir)).map(Int.init)
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

// MARK: - Historique
struct HistoriqueSession: Identifiable {
    let id: String
    let date: String
    let entry: SessionEntry
}
