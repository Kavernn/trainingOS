import SwiftUI
import Combine
import UIKit
import UserNotifications

extension Notification.Name {
    static let sessionCompleted = Notification.Name("trainingos.sessionCompleted")
}

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
    var notes: String = ""
}

private struct DraftSet: Codable {
    var weight: String
    var reps: String
    var rir: Int
    var duration: Int
    var rpe: Double? = nil
}

// MARK: - ExerciseDraftPersistence

private struct ExerciseDraftPersistence {
    let exerciseName: String
    private var key: String { "exo_draft_\(exerciseName)" }

    @discardableResult
    func save(_ drafts: [DraftSet]) -> Bool {
        guard let data = try? APIService.encoder.encode(drafts) else { return false }
        UserDefaults.standard.set(data, forKey: key)
        return true
    }

    func load() -> [DraftSet]? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? APIService.decoder.decode([DraftSet].self, from: data)
    }

    func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

// MARK: - ExerciseCalculator

enum ExerciseCalculator {

    static func setsCount(scheme: String, prescription: ExercisePrescription?) -> Int {
        if let p = prescription { return max(1, min(p.sets, 12)) }
        let s = scheme.lowercased()
        if let x = s.firstIndex(of: "x") {
            let before = String(s[s.startIndex..<x])
            if let n = Int(before) { return max(1, min(n, 12)) }
        }
        return 3
    }

    static func exerciseRPE(sets: [SetInput]) -> Double {
        guard !sets.isEmpty else { return 7.0 }
        let avgRIR = Int((Double(sets.map(\.rir).reduce(0, +)) / Double(sets.count)).rounded())
        return RPEHelper.rirToRPE(min(avgRIR, 4))
    }

    static func totalWeight(for input: Double, equipmentType: String) -> Double {
        switch equipmentType {
        case "bodyweight":               return input
        case "barbell":                  return input * 2 + 45
        case "dumbbell", "cable_double": return input * 2
        default:                         return input
        }
    }

    static func inputHint(currentWeight: Double, equipmentType: String) -> Double {
        guard currentWeight > 0 else { return 0 }
        switch equipmentType {
        case "barbell":                  return max(0, (currentWeight - 45) / 2)
        case "dumbbell", "cable_double": return currentWeight / 2
        case "bodyweight":               return 0
        default:                         return currentWeight
        }
    }

    static func warmupSets(currentWeight: Double) -> [(pct: Int, weight: Double)] {
        guard currentWeight > 0 else { return [] }
        let ud = UserDefaults.standard
        let p1 = ud.object(forKey: "warmup_pct_1") as? Int ?? 40
        let p2 = ud.object(forKey: "warmup_pct_2") as? Int ?? 60
        let p3 = ud.object(forKey: "warmup_pct_3") as? Int ?? 80
        let round2_5: (Double) -> Double = { round($0 / 2.5) * 2.5 }
        return [(p1, round2_5(currentWeight * Double(p1) / 100)),
                (p2, round2_5(currentWeight * Double(p2) / 100)),
                (p3, round2_5(currentWeight * Double(p3) / 100))]
    }

    static func perSetHint(for index: Int, weightData: WeightData?, equipmentType: String) -> String {
        let units = UnitSettings.shared
        let hint = inputHint(currentWeight: weightData?.currentWeight ?? 0, equipmentType: equipmentType)
        if let lastSets = weightData?.history?.first?.sets, index < lastSets.count {
            let w = lastSets[index].weight
            let perSide: Double
            switch equipmentType {
            case "barbell":                  perSide = w > 45 ? (w - 45) / 2 : 0
            case "dumbbell", "cable_double": perSide = w / 2
            case "bodyweight":               return "0.0"
            default:                         perSide = w
            }
            if perSide > 0 { return units.inputStr(perSide) }
        }
        return hint > 0 ? units.inputStr(hint) : "0.0"
    }

    static func formatDuration(_ secs: Int) -> String {
        guard secs >= 60 else { return "\(secs)s" }
        let m = secs / 60; let s = secs % 60
        return s > 0 ? "\(m)m\(s)s" : "\(m)m"
    }

    static func repsStr(sets: [SetInput], isTimeBased: Bool) -> String {
        if isTimeBased { return sets.map { String($0.duration) }.joined(separator: ",") }
        return sets.compactMap { $0.reps.isEmpty ? nil : $0.reps }.joined(separator: ",")
    }
}

// MARK: - ExerciseViewModel

@MainActor
final class ExerciseViewModel: ObservableObject {

    // Config (immutable after init)
    let name: String
    let scheme: String
    let weightData: WeightData?
    @Published var equipmentType: String
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
    // Auto-calculé depuis le RIR moyen des sets (ne plus modifier manuellement)
    var exerciseRPE: Double { ExerciseCalculator.exerciseRPE(sets: sets) }
    @Published var painZone: String = ""
    @Published var setBySetMode: Bool = false
    @Published var currentSetIndex: Int = 0
    @Published var repCountMode: Bool = false
    @Published var showWarmup: Bool = false
    @Published var isLogged = false
    @Published var isEditing = false
    @Published var isSkipped = false
    @Published var sessionNote: String = ""

    @Published private(set) var draftSavedAt: Date? = nil
    // W-B2 — expose network log errors so ExerciseCard can display a banner
    @Published var logError: String? = nil
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

        // W-D9 — reduced debounce from 1.5s to 0.5s for faster draft saves
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
    var isFirstTime: Bool { weightData?.history?.isEmpty ?? true }

    var setsCount: Int { ExerciseCalculator.setsCount(scheme: scheme, prescription: prescription) }

    var avgWeight: Double? {
        var sum = 0.0; var count = 0
        for s in sets {
            if let v = Double(s.weight.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")), v > 0 {
                sum += v; count += 1
            }
        }
        return count > 0 ? sum / Double(count) : nil
    }

    var canLog: Bool {
        if isTimeBased { return sets.contains { $0.duration > 0 } }
        if equipmentType == "bodyweight" {
            return sets.contains { (Int($0.reps) ?? 0) > 0 }
        }
        if equipmentType == "fixed_weight" {
            return sets.contains { s in
                guard let w = Double(s.weight.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")),
                      w > 0 else { return false }
                let repsStr = s.reps.trimmingCharacters(in: .whitespaces)
                return repsStr.isEmpty || (Int(repsStr) ?? 0) > 0
            }
        }
        // Standard : weight >= 0 (0 OK pour exos assistés à contrepoids), reps > 0
        return sets.contains { s in
            guard let w = Double(s.weight.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")),
                  w >= 0 else { return false }
            return (Int(s.reps) ?? 0) > 0
        }
    }

    var repsStr: String { ExerciseCalculator.repsStr(sets: sets, isTimeBased: isTimeBased) }

    var lastRepsParts: [String] { lastReps.split(separator: ",").map(String.init) }

    var warmupSets: [(pct: Int, weight: Double)] { ExerciseCalculator.warmupSets(currentWeight: currentWeight) }

    var inputHint: Double { ExerciseCalculator.inputHint(currentWeight: currentWeight, equipmentType: equipmentType) }

    // MARK: - Draft persistence

    private var draftStore: ExerciseDraftPersistence { ExerciseDraftPersistence(exerciseName: name) }

    private func saveDraft() {
        let draft = sets.map { DraftSet(weight: $0.weight, reps: $0.reps, rir: $0.rir, duration: $0.duration, rpe: $0.rpe) }
        if draftStore.save(draft) { draftSavedAt = Date() }
    }

    private func loadDraft() -> [DraftSet]? { draftStore.load() }

    func clearDraft() {
        draftStore.clear()
        sessionNote = ""
    }

    // MARK: - Methods

    func totalWeight(for input: Double) -> Double { ExerciseCalculator.totalWeight(for: input, equipmentType: equipmentType) }
    func perSetHint(for index: Int) -> String { ExerciseCalculator.perSetHint(for: index, weightData: weightData, equipmentType: equipmentType) }
    func formatDuration(_ secs: Int) -> String { ExerciseCalculator.formatDuration(secs) }

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

    func fillFromLastSession() {
        let parts = lastRepsParts
        let targetCount = max(1, parts.count)
        if sets.count < targetCount {
            sets.append(contentsOf: Array(repeating: SetInput(), count: targetCount - sets.count))
        } else if sets.count > targetCount {
            sets = Array(sets.prefix(targetCount))
        }
        for i in sets.indices {
            sets[i].weight = perSetHint(for: i)
            sets[i].reps = parts.indices.contains(i) ? parts[i] : (parts.first ?? "")
        }
    }

    /// Confirme le set courant avec le compte local de la RepCounterSection. Retourne true si c'était le dernier set.
    func confirmSet(reps: Int) -> Bool {
        guard setBySetMode, currentSetIndex < sets.count else { return false }
        if reps > 0 { sets[currentSetIndex].reps = String(reps) }
        if currentSetIndex < sets.count - 1 {
            currentSetIndex += 1
            return false
        }
        return true
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
        let repsOk = !repsStr.isEmpty || equipmentType == "fixed_weight"
        guard !alreadyLogged || isEditing, canLog, repsOk else { return nil }

        if isEditing { isLogged = false }
        isLogged  = true
        isEditing = false
        logError  = nil   // W-B2 — clear any prior error on successful log
        clearDraft()

        if isTimeBased {
            let setsPayload: [[String: Any]] = sets.map { ["weight": 0, "reps": String($0.duration)] }
            let result = ExerciseLogResult(name: name, weight: 0, reps: repsStr, rpe: exerciseRPE,
                sets: setsPayload, isSecond: isSecondSession, isBonus: isBonusSession,
                equipmentType: "bodyweight", painZone: painZone, notes: sessionNote)
            logStatus = .success(0)
            return result
        }

        let units = UnitSettings.shared
        let avg   = avgWeight ?? (equipmentType == "bodyweight" ? 0.0 : nil)
        guard let avg = avg else { return nil }
        let w     = units.toStorage(avg)
        let total = totalWeight(for: w)
        let isFixedWeight = equipmentType == "fixed_weight"
        let setsPayload: [[String: Any]] = sets.compactMap { s -> [String: Any]? in
            let reps = s.reps.isEmpty ? (isFixedWeight ? "0" : nil) : s.reps
            guard let reps = reps else { return nil }
            let setRPE = s.rpe ?? RPEHelper.rirToRPE(s.rir)
            if equipmentType == "bodyweight" {
                let lest = Double(s.weight.replacingOccurrences(of: ",", with: ".")) ?? 0
                return ["weight": units.toStorage(lest), "reps": reps, "rir": s.rir, "rpe": setRPE]
            }
            guard let sw = Double(s.weight.replacingOccurrences(of: ",", with: ".")), sw > 0 else { return nil }
            let setTotal = totalWeight(for: units.toStorage(sw))
            return ["weight": setTotal, "reps": reps, "rir": s.rir, "rpe": setRPE]
        }
        let repsForResult = repsStr.isEmpty && isFixedWeight ? "0" : repsStr
        let result = ExerciseLogResult(name: name, weight: total, reps: repsForResult, rpe: exerciseRPE,
            sets: setsPayload, isSecond: isSecondSession, isBonus: isBonusSession,
            equipmentType: equipmentType, painZone: painZone, notes: sessionNote)
        logStatus = .success(total)
        return result
    }

    func undoLog() {
        isLogged = false
        isEditing = false
        logStatus = nil
        clearDraft()
    }
}

// MARK: - WorkoutChronoViewModel

final class WorkoutChronoViewModel: ObservableObject {
    @Published var elapsedSeconds: Int = 0
    @Published var isPaused: Bool = false

    private var timer: Timer?
    private var startTime: Date?
    private var pausedAt: Date?
    private var totalPausedDuration: TimeInterval = 0
    private var persistDate: String?
    private var persistSessionType: String?

    func start(date: String, sessionType: String) {
        persistDate = date
        persistSessionType = sessionType
        let now = Date()
        startTime = now
        totalPausedDuration = 0
        isPaused = false
        elapsedSeconds = 0
        SessionDraftStore.saveChronoPausedDuration(date: date, sessionType: sessionType, duration: 0)
        SessionDraftStore.saveChronoIsPaused(date: date, sessionType: sessionType, isPaused: false)
        SessionDraftStore.saveChronoPausedAt(date: date, sessionType: sessionType, pausedAt: nil)
        resumeTimer()
    }

    func restore(date: String, sessionType: String) {
        guard let saved = SessionDraftStore.loadStartedAt(date: date, sessionType: sessionType) else { return }
        persistDate = date
        persistSessionType = sessionType
        startTime = saved
        totalPausedDuration = SessionDraftStore.loadChronoPausedDuration(date: date, sessionType: sessionType)
        let savedIsPaused = SessionDraftStore.loadChronoIsPaused(date: date, sessionType: sessionType)

        if savedIsPaused, let pa = SessionDraftStore.loadChronoPausedAt(date: date, sessionType: sessionType) {
            pausedAt = pa
            elapsedSeconds = Int(max(0, pa.timeIntervalSince(saved) - totalPausedDuration))
            isPaused = true
        } else {
            elapsedSeconds = Int(max(0, Date().timeIntervalSince(saved) - totalPausedDuration))
            isPaused = false
            resumeTimer()
        }
    }

    func togglePause() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if isPaused {
            if let pa = pausedAt {
                totalPausedDuration += Date().timeIntervalSince(pa)
                if let d = persistDate, let st = persistSessionType {
                    SessionDraftStore.saveChronoPausedDuration(date: d, sessionType: st, duration: totalPausedDuration)
                    SessionDraftStore.saveChronoPausedAt(date: d, sessionType: st, pausedAt: nil)
                }
            }
            pausedAt = nil
            isPaused = false
            if let d = persistDate, let st = persistSessionType {
                SessionDraftStore.saveChronoIsPaused(date: d, sessionType: st, isPaused: false)
            }
            resumeTimer()
        } else {
            let now = Date()
            pausedAt = now
            isPaused = true
            timer?.invalidate()
            timer = nil
            if let d = persistDate, let st = persistSessionType {
                SessionDraftStore.saveChronoIsPaused(date: d, sessionType: st, isPaused: true)
                SessionDraftStore.saveChronoPausedAt(date: d, sessionType: st, pausedAt: now)
            }
        }
    }

    var netDurationMinutes: Int {
        max(1, Int(ceil(Double(elapsedSeconds) / 60.0)))
    }

    func stop() -> Int {
        timer?.invalidate()
        timer = nil
        isPaused = false
        return netDurationMinutes
    }

    private func resumeTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let start = self.startTime else { return }
            let elapsed = Int(max(0, Date().timeIntervalSince(start) - self.totalPausedDuration))
            DispatchQueue.main.async { self.elapsedSeconds = elapsed }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
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
    @Published var showSuccess = false {
        didSet { if showSuccess { NotificationCenter.default.post(name: .sessionCompleted, object: nil) } }
    }
    @Published var submitError: String?
    @Published var isResuming = false
    @Published var commitWarning: String?
    @Published var commitWarningStyle: ToastStyle = .error
    @Published private(set) var isFinishing = false
    @Published var prCelebrations: [(name: String, oneRM: Double)] = []

    var sessionStart = Date()
    @Published private(set) var sessionStarted = false
    var draftSessionType: String
    let chrono = WorkoutChronoViewModel()

    var cacheService: CacheService = .shared

    init(draftSessionType: String = "morning") {
        self.draftSessionType = draftSessionType
    }

    func load() async {
        if seanceData == nil,
           let cached = cacheService.load(for: "seance_data"),
           let decoded = try? APIService.decoder.decode(SeanceData.self, from: cached) {
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
            let restoredSets: [[String: Any]] = pending.sets.map { s in
                var entry: [String: Any] = ["weight": s.weight, "reps": s.reps, "rir": s.rir]
                if let r = s.rpe { entry["rpe"] = r }
                return entry
            }
            restored[pending.name] = ExerciseLogResult(
                name: pending.name,
                weight: pending.weight,
                reps: pending.reps,
                rpe: pending.rpe,
                sets: restoredSets,
                isSecond: pending.isSecond,
                isBonus: pending.isBonus,
                equipmentType: pending.equipmentType,
                painZone: pending.painZone
            )
        }
        // Restore sessionStart BEFORE assigning logResults — persistDraftIfNeeded() fires on
        // didSet and would overwrite T0 with Date() if sessionStarted is still false at that point.
        if let saved = SessionDraftStore.loadStartedAt(date: data.todayDate, sessionType: draftSessionType) {
            sessionStart = saved
            sessionStarted = true
            chrono.restore(date: data.todayDate, sessionType: draftSessionType)
        }
        logResults = restored
        if !sessionStarted && !restored.isEmpty {
            sessionStart = Date()
            sessionStarted = true
            SessionDraftStore.saveStartedAt(date: data.todayDate, sessionType: draftSessionType, startedAt: sessionStart)
            chrono.start(date: data.todayDate, sessionType: draftSessionType)
        }
        isResuming = !restored.isEmpty
        if data.alreadyLogged {
            SessionDraftStore.clear(date: data.todayDate, sessionType: draftSessionType)
        }
    }

    func finish(rpe: Double, comment: String, durationMin: Double? = nil, energyPre: Int? = nil, sessionName: String? = nil, bonusSession: Bool = false) async {
        guard !isFinishing else { return }
        isFinishing = true

        // Ask iOS for extra background time so the multi-step save (exercise POSTs + session POST)
        // completes even if the user backgrounds the app immediately after tapping "Terminer".
        var bgTask = UIBackgroundTaskIdentifier.invalid
        bgTask = UIApplication.shared.beginBackgroundTask {
            UIApplication.shared.endBackgroundTask(bgTask)
        }
        defer {
            isFinishing = false
            UIApplication.shared.endBackgroundTask(bgTask)
        }

        let exos = logResults.values.map { "\($0.name) \($0.weight)lbs \($0.reps)" }
        let exerciseLogs: [[String: Any]] = logResults.values.map {
            ["exercise": $0.name, "weight": $0.weight, "reps": $0.reps]
        }
        var failedExercises: [String] = []

        var batchInvalidations: [CacheInvalidation] = []
        for result in logResults.values {
            do {
                let response = try await APIService.shared.logExercise(
                    exercise: result.name, weight: result.weight, reps: result.reps, rpe: result.rpe,
                    sets: result.sets, force: true,
                    isSecond: result.isSecond, isBonus: result.isBonus,
                    equipmentType: result.equipmentType, painZone: result.painZone, notes: result.notes,
                    invalidate: false)
                batchInvalidations.append(.exerciseLogged(isSecond: result.isSecond, isBonus: result.isBonus))
                if response.isPR == true {
                    prCelebrations.append((name: result.name, oneRM: response.oneRM ?? 0))
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
        } catch APIError.serverError(409, _) {
            // Séance déjà enregistrée — double-submit ou retry après crash. Draft nettoyé explicitement.
            if let date = seanceData?.todayDate {
                SessionDraftStore.clear(date: date, sessionType: draftSessionType)
            }
            CacheInvalidation.invalidateBatch(batchInvalidations)
            await APIService.shared.fetchDashboard()
            commitWarning = "Séance déjà enregistrée ✓ — aucune perte de données."
            commitWarningStyle = .success
            showSuccess = true
            return
        } catch {
            submitError = "Erreur lors de l'enregistrement : \(error.localizedDescription)"
            // Draft conservé intentionnellement : les données restent restaurables au redémarrage.
            // Si le POST a abouti malgré l'erreur réseau, alreadyLogged le détectera et nettoiera.
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
            await HealthKitService.shared.saveStrengthWorkout(startDate: sessionStart, endDate: Date())
            showSuccess = true
        } else {
            if let date = seanceData?.todayDate {
                SessionDraftStore.clear(date: date, sessionType: draftSessionType)
            }
            BehaviorTracker.shared.record(.sessionEnd)
            await HealthKitService.shared.saveStrengthWorkout(startDate: sessionStart, endDate: Date())
            showSuccess = true
        }
    }

    func startSession() {
        guard !sessionStarted else { return }
        sessionStart = Date()
        sessionStarted = true
        if let date = seanceData?.todayDate {
            SessionDraftStore.saveStartedAt(date: date, sessionType: draftSessionType, startedAt: sessionStart)
            chrono.start(date: date, sessionType: draftSessionType)
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
            SessionDraftStore.saveStartedAt(date: date, sessionType: draftSessionType, startedAt: sessionStart)
            chrono.start(date: date, sessionType: draftSessionType)
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
                painZone: $0.painZone,
                sets: $0.sets.compactMap { s -> PersistedSet? in
                    guard let w = s["weight"] as? Double,
                          let r = s["reps"] as? String else { return nil }
                    return PersistedSet(
                        weight: w,
                        reps: r,
                        rir: s["rir"] as? Int ?? 3,
                        rpe: s["rpe"] as? Double
                    )
                }
            )
        }
        SessionDraftStore.save(date: date, sessionType: draftSessionType, values: values)
        SessionDraftStore.saveStartedAt(date: date, sessionType: draftSessionType, startedAt: sessionStart)
    }
}
