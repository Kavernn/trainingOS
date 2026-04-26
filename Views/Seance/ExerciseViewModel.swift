import SwiftUI
import Combine
import UserNotifications

// MARK: - Shared models (ex-private types in ExerciseCard)

struct SetInput: Identifiable {
    let id = UUID()
    var weight: String = ""
    var reps: String = ""
    var duration: Int = 30   // seconds, used when isTimeBased
    var rir: Int = 3         // Reps In Reserve
    var rpe: Double? = nil   // Per-set RPE (optionnel)
}

enum LogStatus { case success(Double), stagné, loading, error(String) }

struct ExerciseLogResult {
    let name: String
    let weight: Double
    let reps: String
    var rpe: Double? = nil
    var sets: [[String: Any]] = []
    var isSecond: Bool = false
    var isBonus: Bool = false
    var equipmentType: String = ""
    var painZone: String = ""
}

private struct DraftSet: Codable {
    var weight: String
    var reps: String
    var rir: Int
    var duration: Int
    var rpe: Double? = nil
}

// MARK: - ExerciseViewModel

@MainActor
final class ExerciseViewModel: ObservableObject {

    // Config (immutable after init)
    let name: String
    let scheme: String
    let weightData: WeightData?
    let equipmentType: String
    let trackingType: String
    let bodyWeight: Double
    let isSecondSession: Bool
    let isBonusSession: Bool
    let restSeconds: Int?
    let prescription: ExercisePrescription?
    let suggestion: ProgressionSuggestion?

    // Published state (was @State in ExerciseCard)
    @Published var sets: [SetInput] = []
    @Published var showHistory = false
    @Published var logStatus: LogStatus? = nil
    @Published var exerciseRPE: Double = 7
    @Published var painZone: String = ""
    @Published var setBySetMode: Bool = false
    @Published var currentSetIndex: Int = 0
    @Published var showWarmup: Bool = false
    @Published var isLogged = false
    @Published var isEditing = false
    @Published var isSkipped = false
    @Published var sessionNote: String = ""

    private var cancellables = Set<AnyCancellable>()

    init(name: String, scheme: String, weightData: WeightData?, equipmentType: String = "machine",
         trackingType: String = "reps", bodyWeight: Double = 0,
         isSecondSession: Bool = false, isBonusSession: Bool = false,
         restSeconds: Int? = nil, prescription: ExercisePrescription? = nil,
         suggestion: ProgressionSuggestion? = nil) {
        self.name            = name
        self.scheme          = scheme
        self.weightData      = weightData
        self.equipmentType   = equipmentType
        self.trackingType    = trackingType
        self.bodyWeight      = bodyWeight
        self.isSecondSession = isSecondSession
        self.isBonusSession  = isBonusSession
        self.restSeconds     = restSeconds
        self.prescription    = prescription
        self.suggestion      = suggestion

        $sets
            .dropFirst()
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.saveDraft() }
            .store(in: &cancellables)
    }

    // MARK: - Computed

    var isTimeBased: Bool { trackingType == "time" }
    var currentWeight: Double { weightData?.currentWeight ?? 0 }
    var lastReps: String { weightData?.lastReps ?? "—" }

    var setsCount: Int {
        if let p = prescription { return max(1, min(p.sets, 12)) }
        let s = scheme.lowercased()
        if let x = s.firstIndex(of: "x") {
            let before = String(s[s.startIndex..<x])
            if let n = Int(before) { return max(1, min(n, 12)) }
        }
        return 3
    }

    var avgWeight: Double? {
        let vals = sets
            .compactMap { Double($0.weight.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) }
            .filter { $0 > 0 }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    var canLog: Bool {
        if isTimeBased     { return sets.contains { $0.duration > 0 } }
        if equipmentType == "bodyweight" { return sets.contains { Int($0.reps) != nil } }
        return sets.contains {
            Int($0.reps) != nil &&
            Double($0.weight.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) != nil
        }
    }

    var repsStr: String {
        if isTimeBased { return sets.map { String($0.duration) }.joined(separator: ",") }
        return sets.compactMap { $0.reps.isEmpty ? nil : $0.reps }.joined(separator: ",")
    }

    var lastRepsParts: [String] { lastReps.split(separator: ",").map(String.init) }

    var warmupSets: [(pct: Int, weight: Double)] {
        guard currentWeight > 0 else { return [] }
        return [(40, round(currentWeight * 0.4 / 2.5) * 2.5),
                (60, round(currentWeight * 0.6 / 2.5) * 2.5),
                (80, round(currentWeight * 0.8 / 2.5) * 2.5)]
    }

    var inputHint: Double {
        guard currentWeight > 0 else { return 0 }
        switch equipmentType {
        case "barbell":    return max(0, (currentWeight - 45) / 2)
        case "dumbbell":   return currentWeight / 2
        case "bodyweight": return 0
        default:           return currentWeight
        }
    }

    // MARK: - Draft persistence

    private var draftKey: String { "exo_draft_\(name)" }

    private func saveDraft() {
        let draft = sets.map { DraftSet(weight: $0.weight, reps: $0.reps, rir: $0.rir, duration: $0.duration, rpe: $0.rpe) }
        if let data = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(data, forKey: draftKey)
        }
    }

    private func loadDraft() -> [DraftSet]? {
        guard let data = UserDefaults.standard.data(forKey: draftKey) else { return nil }
        return try? JSONDecoder().decode([DraftSet].self, from: data)
    }

    func clearDraft() {
        UserDefaults.standard.removeObject(forKey: draftKey)
        sessionNote = ""
    }

    // MARK: - Methods

    func totalWeight(for input: Double) -> Double {
        switch equipmentType {
        case "bodyweight": return input
        case "barbell":    return input * 2 + 45
        case "dumbbell":   return input * 2
        default:           return input
        }
    }

    func perSetHint(for index: Int) -> String {
        let units = UnitSettings.shared
        if let lastSets = weightData?.history?.first?.sets, index < lastSets.count {
            let w = lastSets[index].weight
            let perSide: Double
            switch equipmentType {
            case "barbell":    perSide = w > 45 ? (w - 45) / 2 : 0
            case "dumbbell":   perSide = w / 2
            case "bodyweight": return "0.0"
            default:           perSide = w
            }
            if perSide > 0 { return units.inputStr(perSide) }
        }
        return inputHint > 0 ? units.inputStr(inputHint) : "0.0"
    }

    func formatDuration(_ secs: Int) -> String {
        guard secs >= 60 else { return "\(secs)s" }
        let m = secs / 60; let s = secs % 60
        return s > 0 ? "\(m)m\(s)s" : "\(m)m"
    }

    func initializeSets() {
        guard sets.isEmpty else { return }
        if let draft = loadDraft(), !draft.isEmpty {
            sets = draft.map { SetInput(weight: $0.weight, reps: $0.reps, duration: $0.duration, rir: $0.rir, rpe: $0.rpe) }
        } else {
            sets = Array(repeating: SetInput(), count: setsCount)
        }
    }

    func syncSetsCount() {
        if sets.count < setsCount {
            sets.append(contentsOf: Array(repeating: SetInput(), count: setsCount - sets.count))
        } else if sets.count > setsCount {
            sets = Array(sets.prefix(setsCount))
        }
    }

    func resetAfterClear() {
        isLogged  = false
        logStatus = nil
        isEditing = false
        clearDraft()
    }

    // Returns ExerciseLogResult to assign to the binding, or nil if can't log.
    // Caller is responsible for: setting logResult binding, calling onLogged, triggering haptic.
    @discardableResult
    func logExercise(alreadyLoggedViaBinding: Bool) -> ExerciseLogResult? {
        let alreadyLogged = isLogged || alreadyLoggedViaBinding || isSkipped
        guard !alreadyLogged || isEditing, canLog, !repsStr.isEmpty else { return nil }

        if isEditing { isLogged = false }
        isLogged  = true
        isEditing = false
        clearDraft()

        if isTimeBased {
            let setsPayload: [[String: Any]] = sets.map { ["weight": 0, "reps": String($0.duration)] }
            let result = ExerciseLogResult(name: name, weight: 0, reps: repsStr, rpe: exerciseRPE,
                sets: setsPayload, isSecond: isSecondSession, isBonus: isBonusSession,
                equipmentType: "bodyweight", painZone: painZone)
            logStatus = .success(0)
            return result
        }

        let units = UnitSettings.shared
        let avg   = avgWeight ?? (equipmentType == "bodyweight" ? 0.0 : nil)
        guard let avg = avg else { return nil }
        let w     = units.toStorage(avg)
        let total = totalWeight(for: w)
        let setsPayload: [[String: Any]] = sets.compactMap { s -> [String: Any]? in
            guard !s.reps.isEmpty else { return nil }
            if equipmentType == "bodyweight" {
                let lest = Double(s.weight.replacingOccurrences(of: ",", with: ".")) ?? 0
                var entry: [String: Any] = ["weight": units.toStorage(lest), "reps": s.reps, "rir": s.rir]
                if let r = s.rpe { entry["rpe"] = r }
                return entry
            }
            guard let sw = Double(s.weight.replacingOccurrences(of: ",", with: ".")), sw > 0 else { return nil }
            let setTotal = totalWeight(for: units.toStorage(sw))
            var entry: [String: Any] = ["weight": setTotal, "reps": s.reps, "rir": s.rir]
            if let r = s.rpe { entry["rpe"] = r }
            return entry
        }
        let result = ExerciseLogResult(name: name, weight: total, reps: repsStr, rpe: exerciseRPE,
            sets: setsPayload, isSecond: isSecondSession, isBonus: isBonusSession,
            equipmentType: equipmentType, painZone: painZone)
        logStatus = .success(total)
        return result
    }
}

// MARK: - SeanceViewModel

@MainActor
class SeanceViewModel: ObservableObject {
    @Published var seanceData: SeanceData?
    @Published var isLoading = false
    @Published var error: String?
    @Published var logResults: [String: ExerciseLogResult] = [:] {
        didSet { persistDraftIfNeeded() }
    }
    @Published var showSuccess = false
    @Published var submitError: String?
    @Published var isResuming = false
    @Published var commitWarning: String?

    var sessionStart = Date()
    @Published private(set) var sessionStarted = false
    var draftSessionType: String

    var cacheService: CacheService = .shared

    init(draftSessionType: String = "morning") {
        self.draftSessionType = draftSessionType
    }

    func load() async {
        if seanceData == nil,
           let cached = cacheService.load(for: "seance_data"),
           let decoded = try? JSONDecoder().decode(SeanceData.self, from: cached) {
            seanceData = decoded
            restoreLogResults(from: decoded)
        }

        if seanceData == nil { isLoading = true }
        error = nil
        do {
            let fresh = try await APIService.shared.fetchSeanceData()
            seanceData = fresh
            restoreLogResults(from: fresh)
        } catch {
            if seanceData == nil { self.error = error.localizedDescription }
        }
        isLoading = false
    }

    func restoreLogResults(from data: SeanceData) {
        let program = data.fullProgram[data.today] ?? [:]
        var restored: [String: ExerciseLogResult] = [:]
        for exerciseName in program.keys {
            if let first = data.weights[exerciseName]?.history?.first,
               first.date == data.todayDate,
               let w = first.weight, let r = first.reps {
                restored[exerciseName] = ExerciseLogResult(name: exerciseName, weight: w, reps: r)
            }
        }
        for pending in SessionDraftStore.load(date: data.todayDate, sessionType: draftSessionType) {
            restored[pending.name] = ExerciseLogResult(
                name: pending.name,
                weight: pending.weight,
                reps: pending.reps,
                rpe: pending.rpe,
                sets: [],
                isSecond: pending.isSecond,
                isBonus: pending.isBonus,
                equipmentType: pending.equipmentType,
                painZone: pending.painZone
            )
        }
        logResults = restored
        if let restoredStart = SessionDraftStore.loadStartedAt(date: data.todayDate, sessionType: draftSessionType) {
            sessionStart = restoredStart
            sessionStarted = true
        } else if !restored.isEmpty {
            sessionStart = Date()
            sessionStarted = true
        }
        isResuming = !restored.isEmpty
        if data.alreadyLogged {
            SessionDraftStore.clear(date: data.todayDate, sessionType: draftSessionType)
        }
    }

    func finish(rpe: Double, comment: String, durationMin: Double? = nil, energyPre: Int? = nil, sessionName: String? = nil, bonusSession: Bool = false) async {
        let exos = logResults.values.map { "\($0.name) \($0.weight)lbs \($0.reps)" }
        let exerciseLogs: [[String: Any]] = logResults.values.map {
            ["exercise": $0.name, "weight": $0.weight, "reps": $0.reps]
        }
        var failedExercises: [String] = []

        for result in logResults.values {
            do {
                let response = try await APIService.shared.logExercise(
                    exercise: result.name, weight: result.weight, reps: result.reps, rpe: result.rpe,
                    sets: result.sets, force: true,
                    isSecond: result.isSecond, isBonus: result.isBonus,
                    equipmentType: result.equipmentType, painZone: result.painZone)
                if response.isPR == true {
                    let content = UNMutableNotificationContent()
                    content.title = "🏆 Nouveau PR !"
                    content.body  = "\(result.name) — 1RM estimé : \(String(format: "%.1f", response.oneRM ?? 0)) lbs"
                    content.sound = .default
                    let request = UNNotificationRequest(
                        identifier: "pr-\(result.name)-\(Date().timeIntervalSince1970)",
                        content: content, trigger: nil)
                    try? await UNUserNotificationCenter.current().add(request)
                }
            } catch {
                failedExercises.append(result.name)
            }
        }

        do {
            try await APIService.shared.logSession(exos: exos, rpe: rpe, comment: comment,
                                                   durationMin: durationMin, energyPre: energyPre,
                                                   bonusSession: bonusSession, sessionName: sessionName,
                                                   exerciseLogs: exerciseLogs)
        } catch {
            submitError = "Erreur lors de l'enregistrement : \(error.localizedDescription)"
            await APIService.shared.fetchDashboard()
            return
        }

        let verified: Bool
        do {
            let fresh = try await APIService.shared.fetchSeanceData()
            verified = fresh.alreadyLogged
        } catch {
            verified = false
        }

        await APIService.shared.fetchDashboard()
        if !verified {
            submitError = "Séance non confirmée en base — vérifie ta connexion et réessaie."
        } else if !failedExercises.isEmpty {
            if let date = seanceData?.todayDate {
                SessionDraftStore.clear(date: date, sessionType: draftSessionType)
            }
            commitWarning = "\(logResults.count - failedExercises.count) / \(logResults.count) exercices enregistrés. Non sauvegardés : \(failedExercises.joined(separator: ", "))"
            showSuccess = true
        } else {
            if let date = seanceData?.todayDate {
                SessionDraftStore.clear(date: date, sessionType: draftSessionType)
            }
            showSuccess = true
        }
    }

    private func persistDraftIfNeeded() {
        guard let date = seanceData?.todayDate else { return }
        if logResults.isEmpty {
            SessionDraftStore.clear(date: date, sessionType: draftSessionType)
            sessionStarted = false
            return
        }
        if !sessionStarted {
            sessionStart = Date()
            sessionStarted = true
        }
        let values = logResults.values.map {
            PersistedExerciseLogResult(
                name: $0.name,
                weight: $0.weight,
                reps: $0.reps,
                rpe: $0.rpe,
                isSecond: $0.isSecond,
                isBonus: $0.isBonus,
                equipmentType: $0.equipmentType,
                painZone: $0.painZone
            )
        }
        SessionDraftStore.save(date: date, sessionType: draftSessionType, values: values)
        SessionDraftStore.saveStartedAt(date: date, sessionType: draftSessionType, startedAt: sessionStart)
    }
}
