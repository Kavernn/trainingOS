import SwiftUI
import Combine

// MARK: - Shared models (ex-private types in ExerciseCard)

struct SetInput: Identifiable {
    let id = UUID()
    var weight: String = ""
    var reps: String = ""
    var duration: Int = 30   // seconds, used when isTimeBased
    var rir: Int = 3         // Reps In Reserve
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
    @Published var showRestTimer = false
    @Published var logStatus: LogStatus? = nil
    @Published var exerciseRPE: Double = 7
    @Published var painZone: String = ""
    @Published var setBySetMode: Bool = false
    @Published var currentSetIndex: Int = 0
    @Published var showWarmup: Bool = false
    @Published var isLogged = false
    @Published var isEditing = false
    @Published var isSkipped = false

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
        if let p = prescription { return max(1, min(p.sets, 8)) }
        let s = scheme.lowercased()
        if let x = s.firstIndex(of: "x") {
            let before = String(s[s.startIndex..<x])
            if let n = Int(before) { return max(1, min(n, 8)) }
        }
        return 3
    }

    var avgWeight: Double? {
        let vals = sets
            .compactMap { Double($0.weight.replacingOccurrences(of: ",", with: ".")) }
            .filter { $0 > 0 }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    var canLog: Bool {
        if isTimeBased     { return sets.contains { $0.duration > 0 } }
        if equipmentType == "bodyweight" { return sets.contains { !$0.reps.isEmpty } }
        return sets.contains { !$0.weight.isEmpty && !$0.reps.isEmpty }
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
        case "barbell":    return (currentWeight - 45) / 2
        case "dumbbell":   return currentWeight / 2
        case "bodyweight": return 0
        default:           return currentWeight
        }
    }

    // MARK: - Draft persistence

    private var draftKey: String { "exo_draft_\(name)" }

    private func saveDraft() {
        let draft = sets.map { DraftSet(weight: $0.weight, reps: $0.reps, rir: $0.rir, duration: $0.duration) }
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
            sets = draft.map { SetInput(weight: $0.weight, reps: $0.reps, duration: $0.duration, rir: $0.rir) }
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
                return ["weight": units.toStorage(lest), "reps": s.reps, "rir": s.rir]
            }
            guard let sw = Double(s.weight.replacingOccurrences(of: ",", with: ".")), sw > 0 else { return nil }
            let setTotal = totalWeight(for: units.toStorage(sw))
            return ["weight": setTotal, "reps": s.reps, "rir": s.rir]
        }
        let result = ExerciseLogResult(name: name, weight: total, reps: repsStr, rpe: exerciseRPE,
            sets: setsPayload, isSecond: isSecondSession, isBonus: isBonusSession,
            equipmentType: equipmentType, painZone: painZone)
        logStatus = .success(total)
        return result
    }
}
