import Foundation

// MARK: - Session Kind
// Enum ciblé pour distinguer les 3 types de séance. Introduit à l'étape 2b
// (CTA création bonus) — les ~100 littéraux "morning"/"evening" restants dans
// le code sont laissés en String (migration opportuniste au fil des touches).
enum SessionKind: String, Codable, CaseIterable {
    case morning, evening, bonus

    var displayName: String {
        switch self {
        case .morning: return "Matin"
        case .evening: return "Soir"
        case .bonus:   return "Bonus"
        }
    }

    /// Ordre canonique morning → evening → bonus (aligné backend
    /// _SESSION_TYPE_ORDER dans get_today_sessions_all).
    var order: Int {
        switch self {
        case .morning: return 0
        case .evening: return 1
        case .bonus:   return 2
        }
    }
}

// MARK: - Log Exercise Response
struct LogExerciseResponse: Codable {
    let success: Bool?
    let newWeight: Double?
    let oneRM: Double?
    let isPR: Bool?
    let baselineCount: Int?
    let confidence: String?

    enum CodingKeys: String, CodingKey {
        case success
        case newWeight     = "new_weight"
        case oneRM         = "1rm"
        case isPR          = "is_pr"
        case baselineCount = "baseline_count"
        case confidence
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
    let smartGoalsCount: Int
    let fullProgram: [String: [String: SafeString]]
    let nutritionTotals: NutritionTotals
    let nutritionSettings: NutritionSettings?
    let profile: UserProfile
    let totalWorkoutMinToday: Double?
    let hasEveningSession: Bool
    let eveningSessionName: String?
    let secondSessionCompleted: Bool
    let hasBonusSession: Bool
    let bonusSessionName: String?
    let bonusSessionCompleted: Bool
    /// Date de début du mésocycle (YYYY-MM-DD) — source serveur unique
    /// (programs.cycle_start_date). Remplace le @AppStorage local iOS.
    let cycleStartDate: String?
    /// Exos poussés matin→soir today (étape 3b, source unique backend).
    /// Remplace SeanceSplitStore.load(date: today) — même type/sémantique.
    let pushedToEvening: Set<String>
    /// Étape 4 — exos poussés vers bonus today. Même sémantique que pushedToEvening.
    let pushedToBonus: Set<String>
    /// {name: exercise_id} union des sessions du programme (cf. SeanceData.exerciseIds).
    let exerciseIds: [String: String]

    enum CodingKeys: String, CodingKey {
        case today, week
        case todayDate = "today_date"
        case alreadyLoggedToday = "already_logged_today"
        case hasPartialLogs = "has_partial_logs"
        case completed
        case schedule, sessions, goals
        case smartGoalsCount = "smart_goals_count"
        case fullProgram = "full_program"
        case nutritionTotals = "nutrition_totals"
        case nutritionSettings = "nutrition_settings"
        case profile
        case totalWorkoutMinToday = "total_workout_min_today"
        case hasEveningSession = "has_evening_session"
        case eveningSessionName = "evening_session_name"
        case secondSessionCompleted = "second_session_completed"
        case hasBonusSession = "has_bonus_session"
        case bonusSessionName = "bonus_session_name"
        case bonusSessionCompleted = "bonus_session_completed"
        case cycleStartDate = "cycle_start_date"
        case pushedToEvening = "pushed_to_evening"
        case pushedToBonus = "pushed_to_bonus"
        case exerciseIds = "exercise_ids"
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
        smartGoalsCount     = (try? c.decode(Int.self, forKey: .smartGoalsCount)) ?? 0
        fullProgram         = try c.decode([String: [String: SafeString]].self, forKey: .fullProgram)
        nutritionTotals     = try c.decode(NutritionTotals.self, forKey: .nutritionTotals)
        nutritionSettings   = try? c.decode(NutritionSettings.self, forKey: .nutritionSettings)
        profile             = try c.decode(UserProfile.self, forKey: .profile)
        totalWorkoutMinToday = try? c.decode(Double.self, forKey: .totalWorkoutMinToday)
        // Rétrocompatible : cache pré-fix Volet F → false/nil → comportement dashboard actuel.
        hasEveningSession      = (try? c.decode(Bool.self, forKey: .hasEveningSession)) ?? false
        eveningSessionName     = try? c.decode(String.self, forKey: .eveningSessionName)
        secondSessionCompleted = (try? c.decode(Bool.self, forKey: .secondSessionCompleted)) ?? false
        // Bonus session (décision D1 — citoyen de première classe). Rétrocompat cache pré-bonus.
        hasBonusSession        = (try? c.decode(Bool.self, forKey: .hasBonusSession)) ?? false
        bonusSessionName       = try? c.decode(String.self, forKey: .bonusSessionName)
        bonusSessionCompleted  = (try? c.decode(Bool.self, forKey: .bonusSessionCompleted)) ?? false
        cycleStartDate         = try? c.decode(String.self, forKey: .cycleStartDate)
        // Étape 3b — rétrocompat cache pré-3b.
        pushedToEvening        = Set((try? c.decode([String].self, forKey: .pushedToEvening)) ?? [])
        // Étape 4 — rétrocompat cache pré-4.
        pushedToBonus          = Set((try? c.decode([String].self, forKey: .pushedToBonus)) ?? [])
        exerciseIds            = (try? c.decode([String: String].self, forKey: .exerciseIds)) ?? [:]
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
    let sessionCount: Int?

    enum CodingKeys: String, CodingKey {
        case exos, rpe, comment
        case loggedAt      = "logged_at"
        case durationMin   = "duration_min"
        case energyPre     = "energy_pre"
        case sessionVolume = "session_volume"
        case totalReps     = "total_reps"
        case totalSets     = "total_sets"
        case sessionCount  = "session_count"
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
        sessionCount = decodeInt(.sessionCount)
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
    let specificDetail: [String: Int]? // {specific_name: sets} for exercises with muscle_specific set

    enum CodingKeys: String, CodingKey {
        case mev, mav, mrv
        case weeklySets     = "weekly_sets"
        case specificDetail = "specific_detail"
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

// MARK: - Superset
struct SupersetEntry: Codable, Equatable, Hashable {
    let a: String
    let b: String
    let rest: Int?

    enum CodingKeys: String, CodingKey {
        case a = "A"
        case b = "B"
        case rest
    }
}

// MARK: - Seance
struct MesocycleInfo: Codable {
    let week: Int
    let phase: String
    let phaseLabel: String
    let rpeTarget: String
    let note: String

    enum CodingKeys: String, CodingKey {
        case week, phase, note
        case phaseLabel = "phase_label"
        case rpeTarget  = "rpe_target"
    }
}

struct SeanceData: Codable {
    let today: String
    let todayDate: String
    let alreadyLogged: Bool

    let schedule: [String: String]
    let fullProgram: [String: [String: SafeString]]
    let weights: [String: WeightData]
    let week: Int
    let mesocycle: MesocycleInfo?
    let inventoryTypes: [String: String]
    let inventoryTracking: [String: String]
    let inventoryRest: [String: Int]
    let inventoryHints: [String: String]
    let inventorySchemes: [String: String]
    let inventoryMuscleGroups: [String: String]
    let exerciseOrder: [String: [String]]
    let exerciseSupersets: [String: [String: SupersetEntry]]
    let prescriptions: [String: ExercisePrescription]?
    let exerciseSuggestions: [String: ProgressionSuggestion]?
    let loggedTodayNames: Set<String>
    /// Nom soir résolu (override manuel > héritage matin > nil). Backend calcule
    /// via get_today_evening(). Utilisé par les callers de SeanceSoirView pour
    /// passer le vrai nom soir au sheet sans deviner (cf. fix override).
    let eveningSessionName: String?
    /// Exos poussés matin→soir today (étape 3b, source unique backend). Remplace
    /// SeanceSplitStore.load(date: today). Décodé depuis le champ `pushed_to_evening`
    /// du payload. Défaut = Set vide si champ absent (rétrocompat cache pré-3b).
    let pushedToEvening: Set<String>
    /// Étape 4 — exos poussés vers bonus today. Même sémantique que pushedToEvening.
    let pushedToBonus: Set<String>
    /// {name: exercise_id UUID} — union de toutes les sessions du programme.
    /// SOURCE UNIQUE backend (même row exercises que le plan → clés identiques).
    /// iOS lit exerciseIds[name] au tap déplacer, envoie l'id au backend.
    /// Fail fast si nil au tap (doctrine — jamais de matching name→id à l'écrit).
    let exerciseIds: [String: String]

    enum CodingKeys: String, CodingKey {
        case today
        case todayDate = "today_date"
        case alreadyLogged = "already_logged"
        case schedule
        case fullProgram = "full_program"
        case weights, week, mesocycle, prescriptions
        case inventoryTypes       = "inventory_types"
        case inventoryTracking    = "inventory_tracking"
        case inventoryRest        = "inventory_rest"
        case inventoryHints       = "inventory_hints"
        case inventorySchemes     = "inventory_schemes"
        case inventoryMuscleGroups = "inventory_muscle_groups"
        case exerciseOrder        = "exercise_order"
        case exerciseSupersets    = "exercise_supersets"
        case exerciseSuggestions  = "exercise_suggestions"
        case loggedTodayNames     = "logged_today_names"
        case eveningSessionName   = "evening_session_name"
        case pushedToEvening      = "pushed_to_evening"
        case pushedToBonus        = "pushed_to_bonus"
        case exerciseIds          = "exercise_ids"
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
        mesocycle          = try? c.decode(MesocycleInfo.self, forKey: .mesocycle)
        inventoryTypes     = (try? c.decode([String: String].self, forKey: .inventoryTypes))    ?? [:]
        inventoryTracking  = (try? c.decode([String: String].self, forKey: .inventoryTracking)) ?? [:]
        inventoryRest      = (try? c.decode([String: Int].self,    forKey: .inventoryRest))     ?? [:]
        inventoryHints     = (try? c.decode([String: String].self, forKey: .inventoryHints))    ?? [:]
        inventorySchemes   = (try? c.decode([String: String].self, forKey: .inventorySchemes))  ?? [:]
        inventoryMuscleGroups = (try? c.decode([String: String].self, forKey: .inventoryMuscleGroups)) ?? [:]
        exerciseOrder      = (try? c.decode([String: [String]].self, forKey: .exerciseOrder))   ?? [:]
        exerciseSupersets  = (try? c.decode([String: [String: SupersetEntry]].self, forKey: .exerciseSupersets)) ?? [:]
        prescriptions      = try? c.decode([String: ExercisePrescription].self, forKey: .prescriptions)
        exerciseSuggestions = try? c.decode([String: ProgressionSuggestion].self, forKey: .exerciseSuggestions)
        loggedTodayNames   = Set((try? c.decode([String].self, forKey: .loggedTodayNames)) ?? [])
        pushedToEvening    = Set((try? c.decode([String].self, forKey: .pushedToEvening)) ?? [])
        pushedToBonus      = Set((try? c.decode([String].self, forKey: .pushedToBonus)) ?? [])
        exerciseIds        = (try? c.decode([String: String].self, forKey: .exerciseIds)) ?? [:]
        eveningSessionName = try? c.decode(String.self, forKey: .eveningSessionName)
    }

    init(today: String, todayDate: String, alreadyLogged: Bool,
         schedule: [String: String], fullProgram: [String: [String: SafeString]],
         weights: [String: WeightData], week: Int, mesocycle: MesocycleInfo? = nil,
         inventoryTypes: [String: String], inventoryTracking: [String: String] = [:],
         inventoryRest: [String: Int] = [:], inventoryHints: [String: String] = [:],
         inventorySchemes: [String: String] = [:],
         inventoryMuscleGroups: [String: String] = [:],
         exerciseOrder: [String: [String]], exerciseSupersets: [String: [String: SupersetEntry]] = [:],
         prescriptions: [String: ExercisePrescription]? = nil,
         exerciseSuggestions: [String: ProgressionSuggestion]? = nil,
         loggedTodayNames: Set<String> = [],
         eveningSessionName: String? = nil,
         pushedToEvening: Set<String> = [],
         pushedToBonus: Set<String> = [],
         exerciseIds: [String: String] = [:]) {
        self.today               = today
        self.todayDate           = todayDate
        self.alreadyLogged       = alreadyLogged
        self.schedule            = schedule
        self.fullProgram         = fullProgram
        self.weights             = weights
        self.week                = week
        self.mesocycle           = mesocycle
        self.inventoryTypes      = inventoryTypes
        self.inventoryTracking   = inventoryTracking
        self.inventoryRest       = inventoryRest
        self.inventoryHints      = inventoryHints
        self.inventorySchemes    = inventorySchemes
        self.inventoryMuscleGroups = inventoryMuscleGroups
        self.exerciseOrder       = exerciseOrder
        self.exerciseSupersets   = exerciseSupersets
        self.prescriptions       = prescriptions
        self.exerciseSuggestions = exerciseSuggestions
        self.loggedTodayNames    = loggedTodayNames
        self.eveningSessionName  = eveningSessionName
        self.pushedToEvening     = pushedToEvening
        self.pushedToBonus       = pushedToBonus
        self.exerciseIds         = exerciseIds
    }
}

struct SeanceSoirData: Codable {
    let hasEveningSession: Bool
    let today: String                 // alias backend de today_soir — évite rename côté WorkoutSeanceView (.today)
    let todaySoir: String?
    let todayDate: String
    let alreadyLogged: Bool
    let schedule: [String: String]
    let fullProgram: [String: [String: SafeString]]
    let weights: [String: WeightData]
    let week: Int
    let mesocycle: MesocycleInfo?
    let inventoryTypes: [String: String]
    let inventoryTracking: [String: String]
    let inventoryRest: [String: Int]
    let inventoryHints: [String: String]
    let inventorySchemes: [String: String]
    let inventoryMuscleGroups: [String: String]
    let exerciseOrder: [String: [String]]
    let exerciseSupersets: [String: [String: SupersetEntry]]
    let prescriptions: [String: ExercisePrescription]?
    let exerciseSuggestions: [String: ProgressionSuggestion]?
    let loggedTodayNames: Set<String>
    /// Étape 3b — cf. SeanceData.pushedToEvening. Même sémantique.
    let pushedToEvening: Set<String>
    /// Étape 4 — cf. SeanceData.pushedToBonus. Même sémantique.
    let pushedToBonus: Set<String>
    /// Étape 3b — cf. SeanceData.exerciseIds.
    let exerciseIds: [String: String]

    enum CodingKeys: String, CodingKey {
        case hasEveningSession = "has_evening_session"
        case today
        case todaySoir         = "today_soir"
        case todayDate         = "today_date"
        case alreadyLogged     = "already_logged"
        case schedule
        case fullProgram       = "full_program"
        case weights, week, mesocycle, prescriptions
        case inventoryTypes    = "inventory_types"
        case inventoryTracking = "inventory_tracking"
        case inventoryRest     = "inventory_rest"
        case inventoryHints    = "inventory_hints"
        case inventorySchemes  = "inventory_schemes"
        case inventoryMuscleGroups = "inventory_muscle_groups"
        case exerciseOrder     = "exercise_order"
        case exerciseSupersets = "exercise_supersets"
        case exerciseSuggestions = "exercise_suggestions"
        case loggedTodayNames  = "logged_today_names"
        case pushedToEvening   = "pushed_to_evening"
        case pushedToBonus     = "pushed_to_bonus"
        case exerciseIds       = "exercise_ids"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hasEveningSession = (try? c.decode(Bool.self,               forKey: .hasEveningSession)) ?? false
        today             = (try? c.decode(String.self,             forKey: .today))             ?? ""
        todaySoir         =  try? c.decode(String.self,             forKey: .todaySoir)
        todayDate         = (try? c.decode(String.self,             forKey: .todayDate))         ?? ""
        alreadyLogged     = (try? c.decode(Bool.self,               forKey: .alreadyLogged))     ?? false
        schedule          = (try? c.decode([String: String].self,   forKey: .schedule))          ?? [:]
        fullProgram       = (try? c.decode([String: [String: SafeString]].self, forKey: .fullProgram)) ?? [:]
        weights           = (try? c.decode([String: WeightData].self, forKey: .weights))         ?? [:]
        week              = (try? c.decode(Int.self,                forKey: .week))              ?? 0
        mesocycle         = try? c.decode(MesocycleInfo.self, forKey: .mesocycle)
        inventoryTypes    = (try? c.decode([String: String].self,   forKey: .inventoryTypes))    ?? [:]
        inventoryTracking = (try? c.decode([String: String].self,   forKey: .inventoryTracking)) ?? [:]
        inventoryRest     = (try? c.decode([String: Int].self,      forKey: .inventoryRest))     ?? [:]
        inventoryHints    = (try? c.decode([String: String].self,   forKey: .inventoryHints))    ?? [:]
        inventorySchemes  = (try? c.decode([String: String].self,   forKey: .inventorySchemes))  ?? [:]
        inventoryMuscleGroups = (try? c.decode([String: String].self, forKey: .inventoryMuscleGroups)) ?? [:]
        exerciseOrder     = (try? c.decode([String: [String]].self, forKey: .exerciseOrder))     ?? [:]
        exerciseSupersets = (try? c.decode([String: [String: SupersetEntry]].self, forKey: .exerciseSupersets)) ?? [:]
        prescriptions     = try? c.decode([String: ExercisePrescription].self, forKey: .prescriptions)
        exerciseSuggestions = try? c.decode([String: ProgressionSuggestion].self, forKey: .exerciseSuggestions)
        loggedTodayNames  = Set((try? c.decode([String].self, forKey: .loggedTodayNames)) ?? [])
        pushedToEvening   = Set((try? c.decode([String].self, forKey: .pushedToEvening)) ?? [])
        pushedToBonus     = Set((try? c.decode([String].self, forKey: .pushedToBonus)) ?? [])
        exerciseIds       = (try? c.decode([String: String].self, forKey: .exerciseIds)) ?? [:]
    }

    /// Bridge L2 : recompose un SeanceData depuis le payload soir. eveningSessionName=nil
    /// (c'est le soir, pas de "soir d'après"). Retourne nil si early return backend
    /// (has_evening_session=false → today="") pour que la vue affiche l'état "Pas de séance".
    func asSeanceData() -> SeanceData? {
        guard hasEveningSession, !today.isEmpty else { return nil }
        return SeanceData(today: today, todayDate: todayDate, alreadyLogged: alreadyLogged,
                         schedule: schedule, fullProgram: fullProgram, weights: weights,
                         week: week, mesocycle: mesocycle,
                         inventoryTypes: inventoryTypes, inventoryTracking: inventoryTracking,
                         inventoryRest: inventoryRest, inventoryHints: inventoryHints,
                         inventorySchemes: inventorySchemes,
                         inventoryMuscleGroups: inventoryMuscleGroups,
                         exerciseOrder: exerciseOrder,
                         exerciseSupersets: exerciseSupersets,
                         prescriptions: prescriptions,
                         exerciseSuggestions: exerciseSuggestions,
                         loggedTodayNames: loggedTodayNames,
                         eveningSessionName: nil,
                         pushedToEvening: pushedToEvening,
                         pushedToBonus: pushedToBonus,
                         exerciseIds: exerciseIds)
    }
}

/// Étape 4 — payload de GET /api/seance_bonus_data (route dédiée, calquée sur
/// api_seance_soir_data). Cas orphelin-compatible : hasBonusSession=false =
/// aucun exo déplacé + aucune session bonus DB → tout le reste absent du payload.
struct SeanceBonusData: Codable {
    let hasBonusSession: Bool
    let todayBonus: String?
    let todayDate: String
    let alreadyLogged: Bool
    let fullProgram: [String: [String: SafeString]]
    let weights: [String: WeightData]
    let week: Int
    let inventoryTypes: [String: String]
    let inventoryTracking: [String: String]
    let inventoryRest: [String: Int]
    let inventorySchemes: [String: String]
    let inventoryMuscleGroups: [String: String]
    let exerciseOrder: [String: [String]]
    let pushedToBonus: Set<String>
    let exerciseIds: [String: String]

    enum CodingKeys: String, CodingKey {
        case hasBonusSession = "has_bonus_session"
        case todayBonus      = "today_bonus"
        case todayDate       = "today_date"
        case alreadyLogged   = "already_logged"
        case fullProgram     = "full_program"
        case weights, week
        case inventoryTypes  = "inventory_types"
        case inventoryTracking = "inventory_tracking"
        case inventoryRest   = "inventory_rest"
        case inventorySchemes = "inventory_schemes"
        case inventoryMuscleGroups = "inventory_muscle_groups"
        case exerciseOrder   = "exercise_order"
        case pushedToBonus   = "pushed_to_bonus"
        case exerciseIds     = "exercise_ids"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hasBonusSession = (try? c.decode(Bool.self,              forKey: .hasBonusSession)) ?? false
        todayBonus      =  try? c.decode(String.self,            forKey: .todayBonus)
        todayDate       = (try? c.decode(String.self,            forKey: .todayDate))       ?? ""
        alreadyLogged   = (try? c.decode(Bool.self,              forKey: .alreadyLogged))   ?? false
        fullProgram     = (try? c.decode([String: [String: SafeString]].self, forKey: .fullProgram)) ?? [:]
        weights         = (try? c.decode([String: WeightData].self, forKey: .weights))      ?? [:]
        week            = (try? c.decode(Int.self,               forKey: .week))            ?? 0
        inventoryTypes  = (try? c.decode([String: String].self,  forKey: .inventoryTypes))  ?? [:]
        inventoryTracking = (try? c.decode([String: String].self, forKey: .inventoryTracking)) ?? [:]
        inventoryRest   = (try? c.decode([String: Int].self,     forKey: .inventoryRest))   ?? [:]
        inventorySchemes = (try? c.decode([String: String].self, forKey: .inventorySchemes)) ?? [:]
        inventoryMuscleGroups = (try? c.decode([String: String].self, forKey: .inventoryMuscleGroups)) ?? [:]
        exerciseOrder   = (try? c.decode([String: [String]].self, forKey: .exerciseOrder))  ?? [:]
        pushedToBonus   = Set((try? c.decode([String].self, forKey: .pushedToBonus)) ?? [])
        exerciseIds     = (try? c.decode([String: String].self, forKey: .exerciseIds))     ?? [:]
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
    let note: String?           // progression action note (+2.5, stagné…)
    let sessionNotes: String?   // user-written note for this session
    let oneRM: Double?
    let sets: [SetEntry]?       // raw per-set data
    let exerciseVolume: Double? // total volume for this exercise entry
    /// Session d'origine de ce log ("morning" | "evening" | "bonus").
    /// Ajouté 2026-07-20 pour permettre à restoreLogResults matin de filtrer
    /// contre un log soir plus riche du même jour (le tri backend privilégie
    /// la row avec le plus de sets, indistinctement matin/soir). Optionnel :
    /// backward-compat avec caches anciens et anciens builds serveur.
    let sessionType: String?

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
        case sessionNotes   = "notes"
        case sessionType    = "session_type"
    }
}

// MARK: - HIIT
struct HIITEntry: Codable, Identifiable {
    let id: String
    let date: String?
    let sessionType: String?
    let rounds: Int?
    let workTime: Int?
    let restTime: Int?
    let rpe: Double?
    let notes: String?

    init(
        id: String = UUID().uuidString,
        date: String?, sessionType: String?, rounds: Int?,
        workTime: Int?, restTime: Int?, rpe: Double?, notes: String?
    ) {
        self.id          = id
        self.date        = date
        self.sessionType = sessionType
        self.rounds      = rounds
        self.workTime    = workTime
        self.restTime    = restTime
        self.rpe         = rpe
        self.notes       = notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date        = try c.decodeIfPresent(String.self,  forKey: .date)
        sessionType = try c.decodeIfPresent(String.self,  forKey: .sessionType)
        rounds      = try c.decodeIfPresent(Int.self,     forKey: .rounds)
        workTime    = try c.decodeIfPresent(Int.self,     forKey: .workTime)
        restTime    = try c.decodeIfPresent(Int.self,     forKey: .restTime)
        rpe         = try c.decodeIfPresent(Double.self,  forKey: .rpe)
        notes       = try c.decodeIfPresent(String.self,  forKey: .notes)
        id          = UUID().uuidString
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(date,        forKey: .date)
        try c.encodeIfPresent(sessionType, forKey: .sessionType)
        try c.encodeIfPresent(rounds,      forKey: .rounds)
        try c.encodeIfPresent(workTime,    forKey: .workTime)
        try c.encodeIfPresent(restTime,    forKey: .restTime)
        try c.encodeIfPresent(rpe,         forKey: .rpe)
        try c.encodeIfPresent(notes,       forKey: .notes)
    }

    enum CodingKeys: String, CodingKey {
        case date, rounds, rpe, notes
        case sessionType = "session_type"
        case workTime    = "work_time"
        case restTime    = "rest_time"
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

// MARK: - Equipment Conversion

enum EquipmentConversion: Equatable {
    case dumbbellToBarbell
    case barbellToDumbbell
    case machineToFree
    case freeToMachine
    case sameType

    init(from originalType: String, to replacementType: String) {
        let dumbbell  = Set(["dumbbell"])
        let barbell   = Set(["barbell", "ez-bar"])
        let machine   = Set(["machine"])
        let freeTypes = Set(["barbell", "ez-bar", "dumbbell", "cable", "cable_double", "bodyweight"])
        switch (originalType, replacementType) {
        case let (a, b) where dumbbell.contains(a)  && barbell.contains(b):   self = .dumbbellToBarbell
        case let (a, b) where barbell.contains(a)   && dumbbell.contains(b):  self = .barbellToDumbbell
        case let (a, b) where machine.contains(a)   && freeTypes.contains(b): self = .machineToFree
        case let (a, b) where freeTypes.contains(a) && machine.contains(b):   self = .freeToMachine
        default: self = .sameType
        }
    }

    /// Returns an estimated converted weight, or nil when types are not comparable.
    /// All cross-equipment conversions are estimates — never use for progression decisions.
    /// Progression is always tracked per (exercise, equipment) pair.
    func convert(_ weight: Double) -> Double? {
        switch self {
        case .dumbbellToBarbell:
            // Dumbbells demand ~15% more stabilisation effort than a barbell.
            // Applying a 0.85 correction yields a more realistic barbell equivalent.
            return (weight * 2) * 0.85
        case .barbellToDumbbell:
            return (weight / 2) * (1.0 / 0.85)
        default:
            return nil
        }
    }

    /// True for any conversion that is an estimate (not an exact equivalence).
    var isEstimate: Bool {
        self != .sameType
    }

    var requiresWarning: Bool {
        self == .machineToFree || self == .freeToMachine
    }

    /// User-facing note explaining conversion limitations.
    var conversionNote: String? {
        switch self {
        case .dumbbellToBarbell:
            return "Estimation — les haltères exigent plus de stabilisation que la barre"
        case .barbellToDumbbell:
            return "Estimation — barre et haltères ne sont pas directement comparables"
        case .machineToFree, .freeToMachine:
            return "Conversion impossible — patterns neuromusculaires différents"
        default:
            return nil
        }
    }
}

// MARK: - Body Weight
struct BodyWeightEntry: Codable, Identifiable {
    var id: String { date }
    let date: String
    let weight: Double
    let bodyFat: Double?
    let waistCm: Double?
    let neckCm: Double?
    let armsCm: Double?
    let chestCm: Double?
    let thighsCm: Double?
    let hipsCm: Double?

    enum CodingKeys: String, CodingKey {
        case date
        case weight   = "poids"
        case bodyFat  = "body_fat"
        case waistCm  = "waist_cm"
        case neckCm   = "neck_cm"
        case armsCm   = "arms_cm"
        case chestCm  = "chest_cm"
        case thighsCm = "thighs_cm"
        case hipsCm   = "hips_cm"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date     = try c.decode(String.self, forKey: .date)
        weight   = (try? c.decode(Double.self, forKey: .weight))
                ?? Double((try? c.decode(String.self, forKey: .weight)) ?? "")
                ?? 0
        bodyFat  = Self.decodeOptionalDouble(c, key: .bodyFat)
        waistCm  = Self.decodeOptionalDouble(c, key: .waistCm)
        neckCm   = Self.decodeOptionalDouble(c, key: .neckCm)
        armsCm   = Self.decodeOptionalDouble(c, key: .armsCm)
        chestCm  = Self.decodeOptionalDouble(c, key: .chestCm)
        thighsCm = Self.decodeOptionalDouble(c, key: .thighsCm)
        hipsCm   = Self.decodeOptionalDouble(c, key: .hipsCm)
    }

    private static func decodeOptionalDouble(
        _ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys
    ) -> Double? {
        if let v = try? c.decodeIfPresent(Double.self, forKey: key) { return v }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }
}

// MARK: - Cardio Metrics
struct CardioMetrics: Codable {
    let vo2maxEstimated: Double?
    let vo2maxCategory: String?
    let vo2maxTrend: String?
    let thresholdPaceMinPerKm: String?
    let fcZones: FCZones?
    let hrSource: String?
    let zoneDistribution: [String: Double]?
    let acwrCardio: CardioACWR?
    let paceZones: PaceZones?
    let bestPaceSecPerKm: Double?
    let guides: CardioGuides?
    let dataCoverage: CardioCoverage?

    enum CodingKeys: String, CodingKey {
        case vo2maxEstimated     = "vo2max_estimated"
        case vo2maxCategory      = "vo2max_category"
        case vo2maxTrend         = "vo2max_trend"
        case thresholdPaceMinPerKm = "threshold_pace_min_per_km"
        case fcZones             = "fc_zones"
        case hrSource            = "hr_source"
        case zoneDistribution    = "zone_distribution"
        case acwrCardio          = "acwr_cardio"
        case paceZones           = "pace_zones"
        case bestPaceSecPerKm    = "best_pace_sec_per_km"
        case guides
        case dataCoverage        = "data_coverage"
    }
}

struct FCZones: Codable {
    let maxHr: Int
    let zone1: [Int]
    let zone2: [Int]
    let zone3: [Int]
    let zone4: [Int]
    let zone5: [Int]
    enum CodingKeys: String, CodingKey {
        case maxHr = "max_hr"
        case zone1, zone2, zone3, zone4, zone5
    }
}

struct CardioACWR: Codable {
    let ratio: Double
    let acuteLoad: Double
    let chronicLoad: Double
    let zone: String
    enum CodingKeys: String, CodingKey {
        case ratio, zone
        case acuteLoad   = "acute_load"
        case chronicLoad = "chronic_load"
    }
}

struct PaceZones: Codable {
    let easy: String
    let moderate: String
    let tempo: String
    let threshold: String
    let race: String
}

struct CardioGuides: Codable {
    let vo2max: String
    let threshold: String
    let acwr: String
    let zones: String
    let pace: String
}

struct CardioCoverage: Codable {
    let hasFc: Bool
    let hasPace: Bool
    let sessions30d: Int
    let vo2maxSessions: Int
    let hrSource: String
    enum CodingKeys: String, CodingKey {
        case hasFc          = "has_fc"
        case hasPace        = "has_pace"
        case sessions30d    = "sessions_30d"
        case vo2maxSessions = "vo2max_sessions"
        case hrSource       = "hr_source"
    }
}

// MARK: - Unified Cardio History
enum UnifiedCardioEntry: Identifiable {
    case cardio(CardioEntry)
    case hiit(HIITEntry)

    var id: String {
        switch self {
        case .cardio(let e): return "cardio-\(e.id)"
        case .hiit(let e):   return "hiit-\(e.id)"
        }
    }

    var date: String? {
        switch self {
        case .cardio(let e): return e.date
        case .hiit(let e):   return e.date
        }
    }
}

// MARK: - Cardio
struct CardioEntry: Codable, Identifiable {
    let id: String
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
    // GPS tracking fields (nullable — historical entries unaffected)
    let startTime: String?
    let endTime: String?
    let paceAvgSeconds: Int?
    let gpsPoints: [[String: Double]]?
    let coachNote: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date           = try c.decodeIfPresent(String.self,             forKey: .date)
        type           = try c.decodeIfPresent(String.self,             forKey: .type)
        durationMin    = try c.decodeIfPresent(Double.self,             forKey: .durationMin)
        distanceKm     = try c.decodeIfPresent(Double.self,             forKey: .distanceKm)
        avgPace        = try c.decodeIfPresent(String.self,             forKey: .avgPace)
        avgHr          = try c.decodeIfPresent(Double.self,             forKey: .avgHr)
        cadence        = try c.decodeIfPresent(Double.self,             forKey: .cadence)
        calories       = try c.decodeIfPresent(Double.self,             forKey: .calories)
        rpe            = try c.decodeIfPresent(Double.self,             forKey: .rpe)
        notes          = try c.decodeIfPresent(String.self,             forKey: .notes)
        startTime      = try c.decodeIfPresent(String.self,             forKey: .startTime)
        endTime        = try c.decodeIfPresent(String.self,             forKey: .endTime)
        paceAvgSeconds = try c.decodeIfPresent(Int.self,                forKey: .paceAvgSeconds)
        gpsPoints      = try c.decodeIfPresent([[String: Double]].self, forKey: .gpsPoints)
        coachNote      = try c.decodeIfPresent(String.self,             forKey: .coachNote)
        id             = UUID().uuidString
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(date,           forKey: .date)
        try c.encodeIfPresent(type,           forKey: .type)
        try c.encodeIfPresent(durationMin,    forKey: .durationMin)
        try c.encodeIfPresent(distanceKm,     forKey: .distanceKm)
        try c.encodeIfPresent(avgPace,        forKey: .avgPace)
        try c.encodeIfPresent(avgHr,          forKey: .avgHr)
        try c.encodeIfPresent(cadence,        forKey: .cadence)
        try c.encodeIfPresent(calories,       forKey: .calories)
        try c.encodeIfPresent(rpe,            forKey: .rpe)
        try c.encodeIfPresent(notes,          forKey: .notes)
        try c.encodeIfPresent(startTime,      forKey: .startTime)
        try c.encodeIfPresent(endTime,        forKey: .endTime)
        try c.encodeIfPresent(paceAvgSeconds, forKey: .paceAvgSeconds)
        try c.encodeIfPresent(gpsPoints,      forKey: .gpsPoints)
        try c.encodeIfPresent(coachNote,      forKey: .coachNote)
    }

    enum CodingKeys: String, CodingKey {
        case date, type, rpe, notes, cadence, calories
        case durationMin     = "duration_min"
        case distanceKm      = "distance_km"
        case avgPace         = "avg_pace"
        case avgHr           = "avg_hr"
        case startTime       = "start_time"
        case endTime         = "end_time"
        case paceAvgSeconds  = "pace_avg_seconds"
        case gpsPoints       = "gps_points"
        case coachNote       = "coach_note"
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

// MARK: - Stats Expansion Models

struct WeeklyTonnageEntry: Codable, Identifiable {
    var id: String { weekStart }
    let weekStart: String
    let totalVolume: Double
    let sessionCount: Int

    enum CodingKeys: String, CodingKey {
        case weekStart    = "week_start"
        case totalVolume  = "total_volume"
        case sessionCount = "session_count"
    }
}

struct PatternVolumeData: Codable {
    let push: Double?
    let pull: Double?
    let hinge: Double?
    let squat: Double?
    let carry: Double?
    let core: Double?
}

struct OneRMPoint: Codable, Identifiable {
    var id: String { date }
    let date: String
    let oneRM: Double

    enum CodingKeys: String, CodingKey {
        case date
        case oneRM = "one_rm"
    }
}

struct HIITCompletionEntry: Codable, Identifiable {
    var id: String { date + (sessionType ?? "") }
    let date: String
    let sessionType: String?
    let roundsPlanned: Int
    let roundsCompleted: Int
    let rate: Double
    let rpe: Double?

    enum CodingKeys: String, CodingKey {
        case date, rate, rpe
        case sessionType     = "session_type"
        case roundsPlanned   = "rounds_planned"
        case roundsCompleted = "rounds_completed"
    }
}
