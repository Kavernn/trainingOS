import SwiftUI
import Combine
import UIKit
import UserNotifications
import os.log

private let exerciseLogger = Logger(subsystem: "TrainingOS", category: "exercise_viewmodel")

extension Notification.Name {
    static let sessionCompleted = Notification.Name("trainingos.sessionCompleted")
}

// MARK: - Shared models (ex-private types in ExerciseCard)

struct SetInput: Identifiable {
    let id = UUID()
    var weight: String = ""
    var reps: String = ""
    var duration: Int = 30   // seconds, used when isTimeBased
    var durationLeft: Int? = nil    // seconds, left side (unilateral)
    var durationRight: Int? = nil   // seconds, right side (unilateral)
    var distance: String = "" // meters, used when tracking_type == "carry"
    var intensity: String = "" // hauteur (cm) ou distance (m), used when tracking_type == "plyo"
    var rir: Int = 3         // Reps In Reserve
    var rpe: Double? = nil   // Per-set RPE (optionnel)
    // ponytail: tracking_type == "protocol" — bouton Fait binaire. Un log protocol = fait par
    // définition ; annuler = supprimer la ligne (chantier delete transverse, hors ici).
    var protocolCompleted: Bool = false
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
    // Local draft metadata only; never added to the API payload.
    var trackingType: String? = nil
    var scheme: String? = nil
    var isUnilateral: Bool? = nil
}

/// Provenance supplied by the caller, separate from effective UI defaults.
struct ExerciseReconstructionMetadata {
    let scheme: String?
    let trackingType: String?
    let isUnilateral: Bool?
}

/// Read-only conversion of a validated recovery, never a new draft or log.
/// Other tracking modes remain visible as summaries until their forms can
/// represent every optional field without supplying defaults.
struct ExerciseRecoveryHydration {
    let sets: [SetInput]
    let note: String
    let painZone: String

    static func make(_ log: ExerciseLogResult, equipment: String,
                     tracking: String, unilateral: Bool,
                     displayWeight: (Double) -> Double) -> Self? {
        guard tracking == "reps", !unilateral,
              log.trackingType == nil || log.trackingType == tracking,
              log.equipmentType == equipment,
              ["machine", "bodyweight", "barbell", "dumbbell", "cable_double"].contains(equipment),
              !log.sets.isEmpty else { return nil }
        var inputs: [SetInput] = []
        for raw in log.sets {
            guard Set(raw.keys).isSubset(of: ["weight", "reps", "rir", "rpe"]),
                  let weight = raw["weight"] as? Double, weight.isFinite, weight >= 0,
                  let reps = raw.repsString(), let count = Int(reps), count > 0,
                  let rir = raw["rir"] as? Int, (0...4).contains(rir),
                  let rpe = raw["rpe"] as? Double, rpe.isFinite else { return nil }
            let input: Double
            switch equipment {
            case "barbell":
                guard weight >= 45 else { return nil }
                input = (weight - 45) / 2
            case "dumbbell", "cable_double": input = weight / 2
            default: input = weight
            }
            let displayed = displayWeight(input)
            guard displayed.isFinite else { return nil }
            // duration/protocol are inapplicable to this explicitly resolved reps form.
            inputs.append(SetInput(weight: String(displayed), reps: reps,
                                   duration: 0, rir: rir, rpe: rpe))
        }
        guard inputs.map(\.reps).joined(separator: ",") == log.reps else { return nil }
        return Self(sets: inputs, note: log.notes, painZone: log.painZone)
    }
}

struct DraftSet: Codable {
    var weight: String
    var reps: String
    var rir: Int
    var duration: Int
    var rpe: Double? = nil
    var distance: String? = nil
    var intensity: String? = nil
    var durationLeft: Int? = nil
    var durationRight: Int? = nil
    var protocolCompleted: Bool? = nil
}

// MARK: - ExerciseDraftPersistence

struct ExerciseCardDraft: Codable {
    var sets: [DraftSet]
    var sessionNote: String? = nil
}

// Draft par carte d'exercice. Scopé par (date, session_type, name) pour éviter
// qu'un draft matin fuite en soir (crime Volet C — l'app se positionnait au 3e set
// avec les valeurs matin déjà "loggées" sans geste utilisateur).
struct ExerciseDraftPersistence {
    let date: String
    let sessionType: String
    let exerciseName: String

    static let keyPrefix = "exo_draft_"
    private var key: String { "\(Self.keyPrefix)\(date)_\(sessionType)_\(exerciseName)" }

    @discardableResult
    func save(_ drafts: [DraftSet], sessionNote: String? = nil) -> Bool {
        guard let data = try? APIService.encoder.encode(ExerciseCardDraft(sets: drafts, sessionNote: sessionNote)) else { return false }
        UserDefaults.standard.set(data, forKey: key)
        return true
    }

    func load() -> [DraftSet]? {
        loadCard()?.sets
    }

    func loadCard() -> ExerciseCardDraft? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        if let draft = try? APIService.decoder.decode(ExerciseCardDraft.self, from: data) { return draft }
        // Existing drafts stored only the set array under this same key.
        guard let sets = try? APIService.decoder.decode([DraftSet].self, from: data) else { return nil }
        return ExerciseCardDraft(sets: sets)
    }

    func clear() { UserDefaults.standard.removeObject(forKey: key) }

    /// Purge : (a) tous les drafts au ancien format "exo_draft_<name>" (orphelins
    /// par le changement de clé), (b) les drafts nouveau format dont la date < currentDate.
    /// Appelée au démarrage app à côté de SeanceSplitStore.purgeOldEntries.
    static func purgeOldExerciseDrafts(currentDate: String) {
        let defaults = UserDefaults.standard
        for k in defaults.dictionaryRepresentation().keys where k.hasPrefix(keyPrefix) {
            let suffix = String(k.dropFirst(keyPrefix.count))
            // Nouveau format : "<date>_<sessionType>_<name>" — 1er segment = date ISO 10 char.
            let firstUnderscore = suffix.firstIndex(of: "_")
            let firstSegment = firstUnderscore.map { String(suffix[suffix.startIndex..<$0]) } ?? suffix
            let isNewFormat = firstSegment.count == 10 && firstSegment.split(separator: "-").count == 3
            if isNewFormat {
                if firstSegment < currentDate {
                    defaults.removeObject(forKey: k)
                }
            } else {
                // Ancien format sans date → orphelin, purge inconditionnelle
                defaults.removeObject(forKey: k)
            }
        }
    }
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

    // "4x40m" → 40. Nil sinon. Placeholder du champ Distance (carry).
    static func distanceTarget(scheme: String) -> Int? {
        let s = scheme.lowercased()
        guard let x = s.firstIndex(of: "x") else { return nil }
        let after = s[s.index(after: x)...]
        let digits = after.prefix { $0.isNumber }
        guard let n = Int(digits), n > 0,
              after.dropFirst(digits.count).hasPrefix("m") else { return nil }
        return n
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

    /// Valeur exacte par côté extraite des sets bruts de la dernière séance.
    /// Renvoie nil UNIQUEMENT si les sets bruts sont absents (pas de données historiques
    /// disponibles pour ce set). "0.0" est une valeur exacte légitime — ex : barbell à la
    /// barre seule (45 lbs total → 0 par côté), bodyweight sans charge additionnelle.
    /// Sert la restitution stricte (fillFromLastSession) ET le hint indicatif (perSetHint).
    static func perSideExact(for index: Int, weightData: WeightData?, equipmentType: String) -> String? {
        guard let lastSets = weightData?.history?.first?.sets,
              index < lastSets.count else { return nil }
        let w = lastSets[index].weight
        let perSide: Double
        switch equipmentType {
        case "barbell":                  perSide = w > 45 ? (w - 45) / 2 : 0
        case "dumbbell", "cable_double": perSide = w / 2
        case "bodyweight":               perSide = w
        default:                         perSide = w
        }
        return UnitSettings.shared.inputStr(perSide)
    }

    static func perSetHint(for index: Int, weightData: WeightData?, equipmentType: String) -> String {
        // Comportement strictement inchangé vs pré-refactor :
        // - sets absents → tombe sur hint (moyenne / currentWeight).
        // - sets présents + bodyweight → "0.0" (usage attendu par les suggestions).
        // - sets présents + perSide = 0 (barre seule) → hint fallback (perSide 0 n'est pas
        //   une SUGGESTION utile ; la restitution stricte utilise perSideExact directement).
        if let exact = perSideExact(for: index, weightData: weightData, equipmentType: equipmentType),
           equipmentType == "bodyweight" || (Double(exact) ?? 0) > 0 {
            return exact
        }
        let units = UnitSettings.shared
        let hint = inputHint(currentWeight: weightData?.currentWeight ?? 0, equipmentType: equipmentType)
        return hint > 0 ? units.inputStr(hint) : "0.0"
    }

    static func formatDuration(_ secs: Int) -> String {
        guard secs >= 60 else { return "\(secs)s" }
        let m = secs / 60; let s = secs % 60
        return s > 0 ? "\(m)m\(s)s" : "\(m)m"
    }

    // ponytail: liste plyo horizontale — 2 entrées. Migrer vers colonne
    // catalogue si >~10 exos ou classification dynamique côté Vince.
    private static let plyoHorizontal: Set<String> = ["Broad Jump", "Lateral Bound"]
    static func plyoUnitLabel(for name: String) -> String {
        plyoHorizontal.contains(name) ? "m" : "cm"   // default cm (vertical)
    }
    static func plyoMetricLabel(for name: String) -> String {
        plyoHorizontal.contains(name) ? "Distance (m)" : "Hauteur (cm)"
    }

    static func repsStr(sets: [SetInput], trackingType: String = "reps", isUnilateral: Bool = false) -> String {
        // Switch exhaustif — une branche par tracking_type (7 valeurs CHECK DB 087a).
        // Default = fatal (assert dev + logger prod) : un type inconnu n'est jamais silencieux.
        switch trackingType {
        case "reps", "plyo":
            // plyo (sauts par set) = même sémantique CSV que reps.
            return sets.compactMap { $0.reps.isEmpty ? nil : $0.reps }.joined(separator: ",")
        case "time":
            return sets.map { s in
                isUnilateral
                    ? String((s.durationLeft ?? 0) + (s.durationRight ?? 0))
                    : String(s.duration)
            }.joined(separator: ",")
        case "carry":
            return sets.compactMap { $0.distance.isEmpty ? nil : $0.distance }.joined(separator: ",")
        case "protocol", "interval", "cardio":
            // Placeholder canLog + backend reps_str NOT NULL (workout_logging.py:83).
            // Vraie donnée = duration/intensity/distance (colonnes top-level 087a).
            return "1"
        default:
            assertionFailure("repsStr: trackingType inconnu \(trackingType)")
            exerciseLogger.error("repsStr: trackingType inconnu \(trackingType, privacy: .public)")
            return "1"
        }
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
    let isUnilateral: Bool
    let bodyWeight: Double
    let isSecondSession: Bool
    let isBonusSession: Bool
    let restSeconds: Int?
    let prescription: ExercisePrescription?
    let suggestion: ProgressionSuggestion?
    let sessionDate: String
    let reconstructionMetadata: ExerciseReconstructionMetadata?

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
    @Published var sessionNote: String = "" {
        didSet { if !isClearingDraft && !isHydratingRecovery { saveDraft() } }
    }
    private var isClearingDraft = false
    private var isHydratingRecovery = false
    private var didHydrateRecovery = false

    @Published private(set) var draftSavedAt: Date? = nil
    // W-B2 — expose network log errors so ExerciseCard can display a banner
    @Published var logError: String? = nil
    private var cancellables = Set<AnyCancellable>()

    init(name: String, scheme: String, weightData: WeightData?, equipmentType: String = "machine",
         trackingType: String = "reps", isUnilateral: Bool = false, bodyWeight: Double = 0,
         isSecondSession: Bool = false, isBonusSession: Bool = false,
         restSeconds: Int? = nil, prescription: ExercisePrescription? = nil,
         suggestion: ProgressionSuggestion? = nil,
         sessionDate: String = "", reconstructionMetadata: ExerciseReconstructionMetadata? = nil) {
        self.reconstructionMetadata = reconstructionMetadata
        self.name            = name
        self.scheme          = scheme
        self.weightData      = weightData
        self.equipmentType   = equipmentType
        self.trackingType    = trackingType
        self.isUnilateral    = isUnilateral
        self.bodyWeight      = bodyWeight
        self.isSecondSession = isSecondSession
        self.isBonusSession  = isBonusSession
        self.restSeconds     = restSeconds
        self.prescription    = prescription
        self.suggestion      = suggestion
        self.sessionDate     = sessionDate

        // W-D9 — reduced debounce from 1.5s to 0.5s for faster draft saves
        $sets
            .dropFirst()
            .filter { [weak self] _ in self?.isHydratingRecovery != true }
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

    var canLog: Bool { logBlockedReason() == nil }

    var repsStr: String { ExerciseCalculator.repsStr(sets: sets, trackingType: trackingType, isUnilateral: isUnilateral) }

    var lastRepsParts: [String] { lastReps.split(separator: ",").map(String.init) }

    var warmupSets: [(pct: Int, weight: Double)] { ExerciseCalculator.warmupSets(currentWeight: currentWeight) }

    var inputHint: Double { ExerciseCalculator.inputHint(currentWeight: currentWeight, equipmentType: equipmentType) }

    // MARK: - Progressive Overload (comparaison live vs dernière séance)

    /// Baseline de progression = dernière séance d'un jour ANTÉRIEUR (date < sessionDate).
    /// La séance 2 ne se compare jamais au matin même (volume complémentaire ≠ compétition
    /// intra-jour). Décision Vince 2026-07-13.
    /// Dégradation douce si sessionDate indisponible ("") → history.first (comportement pré-fix).
    private func firstPriorHistoryEntry() -> WeightHistoryEntry? {
        guard let history = weightData?.history else { return nil }
        guard !sessionDate.isEmpty else { return history.first }
        return history.first(where: { ($0.date ?? "") < sessionDate })
    }

    /// Feature désactivée pour tracking par temps uniquement.
    /// Bodyweight pur : target volume nil (v=0), overload reste actif sur les reps.
    /// Bodyweight lesté : target volume et reps disponibles via sets_json historiques.
    /// Nouvel exo (aucun historique) : les deux targets sont nil → overload caché.
    var overloadEnabled: Bool {
        guard !isTimeBased else { return false }
        return overloadTargetReps != nil || overloadTargetVolumeLbs != nil
    }

    /// Σ reps de tous les sets de la dernière occurrence ANTÉRIEURE de cet exo. nil si history vide.
    var overloadTargetReps: Int? {
        guard let last = firstPriorHistoryEntry()?.sets, !last.isEmpty else { return nil }
        var total = 0
        for s in last {
            if let r = Int(s.reps.trimmingCharacters(in: .whitespaces)) { total += r }
        }
        return total > 0 ? total : nil
    }

    /// Volume total (LBS storage) de la dernière occurrence ANTÉRIEURE, calculé à la lecture backend.
    var overloadTargetVolumeLbs: Double? {
        guard let v = firstPriorHistoryEntry()?.exerciseVolume, v > 0 else { return nil }
        return v
    }

    /// Σ reps saisies dans les sets en cours. Entrées vides ou invalides ignorées.
    var overloadCurrentReps: Int {
        var total = 0
        for s in sets {
            if let r = Int(s.reps.trimmingCharacters(in: .whitespaces)), r > 0 { total += r }
        }
        return total
    }

    /// Volume live en LBS storage. Miroir strict de la formule logExercise :
    /// input display → UnitSettings.toStorage(LBS) → totalWeight(equipmentType) × reps.
    /// C'est cette formule qui doit être utilisée pour rester comparable au
    /// exerciseVolume calculé côté backend.
    var overloadCurrentVolumeLbs: Double {
        let units = UnitSettings.shared
        var total = 0.0
        for s in sets {
            let wStr = s.weight.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
            guard let wDisplay = Double(wStr), wDisplay > 0 else { continue }
            guard let reps = Int(s.reps.trimmingCharacters(in: .whitespaces)), reps > 0 else { continue }
            let setTotal = ExerciseCalculator.totalWeight(for: units.toStorage(wDisplay), equipmentType: equipmentType)
            total += setTotal * Double(reps)
        }
        return total
    }

    /// Vrai dès qu'une des deux cibles est STRICTEMENT dépassée.
    /// Égaler la dernière séance ne compte pas.
    var overloadReached: Bool {
        if let t = overloadTargetReps,      overloadCurrentReps      > t { return true }
        if let t = overloadTargetVolumeLbs, overloadCurrentVolumeLbs > t { return true }
        return false
    }

    // MARK: - Draft persistence

    private var sessionTypeForDraft: String {
        if isBonusSession { return "bonus" }
        if isSecondSession { return "evening" }
        return "morning"
    }
    private var draftStore: ExerciseDraftPersistence {
        ExerciseDraftPersistence(date: sessionDate, sessionType: sessionTypeForDraft, exerciseName: name)
    }

    private func saveDraft() {
        let draft = sets.map {
            DraftSet(weight: $0.weight, reps: $0.reps, rir: $0.rir, duration: $0.duration, rpe: $0.rpe,
                     distance: $0.distance.isEmpty ? nil : $0.distance,
                     intensity: $0.intensity.isEmpty ? nil : $0.intensity,
                     durationLeft: $0.durationLeft, durationRight: $0.durationRight,
                     protocolCompleted: $0.protocolCompleted ? true : nil)
        }
        if draftStore.save(draft, sessionNote: sessionNote) { draftSavedAt = Date() }
    }

    func clearDraft() {
        isClearingDraft = true
        defer { isClearingDraft = false }
        draftStore.clear()
        sessionNote = ""
    }

    // MARK: - Methods

    func totalWeight(for input: Double) -> Double { ExerciseCalculator.totalWeight(for: input, equipmentType: equipmentType) }
    func perSetHint(for index: Int) -> String { ExerciseCalculator.perSetHint(for: index, weightData: weightData, equipmentType: equipmentType) }
    func formatDuration(_ secs: Int) -> String { ExerciseCalculator.formatDuration(secs) }

    func initializeRecovery(_ recovery: ExerciseRecoveryHydration) {
        guard !didHydrateRecovery, sets.isEmpty else { return }
        didHydrateRecovery = true
        isHydratingRecovery = true
        defer { isHydratingRecovery = false }
        // A real edit saved after recovery takes precedence on a later recreation.
        if let draft = draftStore.loadCard(), !draft.sets.isEmpty {
            sets = draft.sets.map {
                SetInput(weight: $0.weight, reps: $0.reps, duration: $0.duration,
                         durationLeft: $0.durationLeft, durationRight: $0.durationRight,
                         distance: $0.distance ?? "", intensity: $0.intensity ?? "",
                         rir: $0.rir, rpe: $0.rpe, protocolCompleted: $0.protocolCompleted ?? false)
            }
            sessionNote = draft.sessionNote ?? recovery.note
        } else {
            sets = recovery.sets
            sessionNote = recovery.note
        }
        painZone = recovery.painZone
    }

    func initializeSets() {
        guard sets.isEmpty else { return }
        let draft = draftStore.loadCard()
        if let draft, !draft.sets.isEmpty {
            sets = draft.sets.map {
                SetInput(weight: $0.weight, reps: $0.reps, duration: $0.duration,
                         durationLeft: $0.durationLeft, durationRight: $0.durationRight,
                         distance: $0.distance ?? "", intensity: $0.intensity ?? "",
                         rir: $0.rir, rpe: $0.rpe, protocolCompleted: $0.protocolCompleted ?? false)
            }
        } else {
            sets = Array(repeating: SetInput(), count: setsCount)
        }
        sessionNote = draft?.sessionNote ?? ""
        if !isTimeBased && !sets.isEmpty {
            setBySetMode = true
            // Reprend au 1er set incomplet ; si tous remplis (✓ final pas tapé),
            // reste sur le dernier — prêt à valider.
            currentSetIndex = firstIncompleteSetIndex() ?? max(0, sets.count - 1)
        }
    }

    func syncSetsCount() {
        guard !didHydrateRecovery else { return }
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
            // Restitution stricte : lit sets bruts par set. Fallback CHAMP VIDE, jamais
            // la moyenne. Restituer une moyenne (currentWeight agrégé) comme "ce que tu as
            // fait" est un mensonge (crime prouvé : Bench 71,7 lbs uniformes sur 3 sets).
            // "0.0" reste une restitution valide (barre seule, bodyweight).
            sets[i].weight = ExerciseCalculator.perSideExact(for: i, weightData: weightData, equipmentType: equipmentType) ?? ""
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

    /// Vrai si le set est jugé "complet" selon equipmentType. USAGE INTERNE
    /// setBySetMode uniquement (via firstIncompleteSetIndex → initializeSets).
    /// HORS chemin du log : la validation au log passe par logBlockedReason().
    private func isSetComplete(_ s: SetInput) -> Bool {
        if isTimeBased {
            return isUnilateral
                ? ((s.durationLeft ?? 0) > 0 && (s.durationRight ?? 0) > 0)
                : (s.duration > 0)
        }
        let weightStr = s.weight.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let repsTrimmed = s.reps.trimmingCharacters(in: .whitespaces)
        switch equipmentType {
        case "bodyweight":
            return !repsTrimmed.isEmpty
        case "fixed_weight":
            return (Double(weightStr) ?? 0) > 0
        default:
            return (Double(weightStr) ?? 0) > 0 && !repsTrimmed.isEmpty
        }
    }

    /// Index du premier set incomplet. Sert à reprendre au bon endroit après crash.
    private func firstIncompleteSetIndex() -> Int? {
        sets.firstIndex(where: { !isSetComplete($0) })
    }

    /// Source unique de vérité "cet exo est-il loggable dans son état actuel ?"
    /// Retourne nil si loggable, sinon message d'erreur à afficher.
    /// UNE branche par tracking_type (7 valeurs CHECK DB 087a), exhaustive.
    /// Default = fatal (assert dev + logger prod + message visible) : un nouveau
    /// type non géré casse en dev, jamais silencieux en prod. Le CHECK DB est
    /// la ceinture, ce switch est la bretelle.
    func logBlockedReason() -> String? {
        switch trackingType {
        case "reps":
            return firstIncompleteRepsSet()
        case "time":
            if isUnilateral {
                // Option B : un set entamé doit avoir ses 2 côtés. Bloquer au 1er demi-set.
                let halfIdx = sets.firstIndex {
                    let l = ($0.durationLeft ?? 0) > 0
                    let r = ($0.durationRight ?? 0) > 0
                    return l != r
                }
                if let i = halfIdx {
                    let missing = (sets[i].durationLeft ?? 0) == 0 ? "gauche" : "droite"
                    return "Set \(i + 1) : côté \(missing) manquant"
                }
                let anyComplete = sets.contains {
                    ($0.durationLeft ?? 0) > 0 && ($0.durationRight ?? 0) > 0
                }
                return anyComplete ? nil : "Durée requise (gauche et droite)"
            }
            return sets.contains { $0.duration > 0 } ? nil : "Durée requise"
        case "carry":
            return sets.contains { (Int($0.distance) ?? 0) > 0 } ? nil : "Distance requise"
        case "plyo":
            // plyo = sauts par set (reps int) + hauteur/distance (intensity double,
            // unité résolue par l'exo côté vue). Les deux dimensions requises.
            let repsOK = sets.contains { (Int($0.reps) ?? 0) > 0 }
            let intOK  = sets.contains { (Double($0.intensity.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0 }
            if !repsOK { return "Nombre de sauts requis" }
            if !intOK  { return "Hauteur/distance requise" }
            return nil
        case "cardio":
            return (sets.first?.duration ?? 0) > 0 ? nil : "Durée requise"
        case "interval":
            return sets.first?.protocolCompleted == true ? nil : "Marquer comme fait"
        case "protocol":
            return sets.first?.protocolCompleted == true ? nil : "Marquer comme fait"
        default:
            assertionFailure("logBlockedReason: trackingType inconnu \(trackingType)")
            exerciseLogger.error("logBlockedReason: trackingType inconnu \(self.trackingType, privacy: .public)")
            return "Type non pris en charge : \(trackingType)"
        }
    }

    /// Reps standard : itère les sets, retourne "Set N : …" au premier partiellement
    /// rempli selon equipmentType. Un set ENTIÈREMENT vide (weight="" ET reps="") est
    /// SKIPPÉ — permet une séance écourtée (3/4 sets faits, 4e non tenté). Aligné
    /// avec le compactMap de logExercise :~600 qui drop déjà silencieusement les sets
    /// vides du payload. Si aucun set n'est commencé, retourne un hint générique.
    private func firstIncompleteRepsSet() -> String? {
        var anyStarted = false
        for (i, s) in sets.enumerated() {
            let weightStr = s.weight.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
            let repsTrimmed = s.reps.trimmingCharacters(in: .whitespaces)
            if weightStr.isEmpty && repsTrimmed.isEmpty { continue }
            anyStarted = true
            let n = i + 1
            switch equipmentType {
            case "bodyweight":
                if repsTrimmed.isEmpty { return "Set \(n) : reps requises" }
            case "fixed_weight":
                if (Double(weightStr) ?? 0) <= 0 { return "Set \(n) : poids requis" }
            default:
                if (Double(weightStr) ?? 0) <= 0 { return "Set \(n) : poids requis" }
                if repsTrimmed.isEmpty { return "Set \(n) : reps requises" }
            }
        }
        return anyStarted ? nil : "Entre poids et reps pour logger"
    }

    // Returns ExerciseLogResult to assign to the binding, or nil if can't log.
    // Caller is responsible for: setting logResult binding, calling onLogged, triggering haptic.
    private func withReconstructionMetadata(_ log: ExerciseLogResult) -> ExerciseLogResult {
        var result = log
        // Certify only values matching the configuration actually used by this VM.
        if let metadata = reconstructionMetadata {
            result.scheme = metadata.scheme == scheme ? metadata.scheme : nil
            result.isUnilateral = metadata.isUnilateral == isUnilateral ? metadata.isUnilateral : nil
            if metadata.trackingType == trackingType { result.trackingType = metadata.trackingType }
        }
        // These branches cannot be entered through the default UI "reps" fallback.
        if ["time", "plyo", "carry", "protocol"].contains(trackingType) {
            result.trackingType = trackingType
        }
        return result
    }

    @discardableResult
    func logExercise(alreadyLoggedViaBinding: Bool) -> ExerciseLogResult? {
        let alreadyLogged = isLogged || alreadyLoggedViaBinding || isSkipped
        guard !alreadyLogged || isEditing else { return nil }

        if let reason = logBlockedReason() {
            logError = reason
            return nil
        }

        if isEditing { isLogged = false }
        isLogged  = true
        isEditing = false
        logError  = nil   // W-B2 — clear any prior error on successful log
        let noteForResult = sessionNote
        defer { clearDraft() }

        if trackingType == "protocol" {
            // ponytail: log protocol = fait par définition. reps="1" placeholder canLog + NOT NULL,
            // PAS 1 rep. _skip_tonnage backend ignore le volume. Source vérité = colonne top-level
            // protocol_completed (dérivée backend via P9 sur base du tracking_type). setsPayload
            // volontairement minimal — pas de protocol_completed dans sets_json (jamais lu).
            let setsPayload: [[String: Any]] = [["weight": 0]]
            let result = ExerciseLogResult(name: name, weight: 0, reps: "1", rpe: exerciseRPE,
                sets: setsPayload, isSecond: isSecondSession, isBonus: isBonusSession,
                equipmentType: equipmentType, painZone: painZone, notes: noteForResult, trackingType: trackingType)
            logStatus = .success(0)
            return withReconstructionMetadata(result)
        }

        if trackingType == "carry" {
            // ponytail: repsStr = distances jointes en CSV pour satisfaire canLog/repsOk.
            // Ce ne SONT PAS des reps — _skip_tonnage backend skip le volume. Source vérité
            // distance = sets_json.distance_m + colonne exercise_logs.distance_m (top-level).
            let units = UnitSettings.shared
            let setsPayload: [[String: Any]] = sets.compactMap { s -> [String: Any]? in
                guard let d = Int(s.distance), d > 0 else { return nil }
                let sw = Double(s.weight.replacingOccurrences(of: ",", with: ".")) ?? 0
                let setTotal = totalWeight(for: units.toStorage(sw))
                return ["weight": setTotal, "distance_m": d]
            }
            let repsCSV = sets.map(\.distance).filter { !$0.isEmpty }.joined(separator: ",")
            // Aligné backend workout_logging.py:111-115 (1re série non-nulle).
            let firstW = setsPayload.compactMap { $0["weight"] as? Double }.first(where: { $0 > 0 }) ?? 0
            let result = ExerciseLogResult(name: name, weight: firstW, reps: repsCSV, rpe: exerciseRPE,
                sets: setsPayload, isSecond: isSecondSession, isBonus: isBonusSession,
                equipmentType: equipmentType, painZone: painZone, notes: noteForResult, trackingType: trackingType)
            logStatus = .success(firstW)
            return withReconstructionMetadata(result)
        }

        if trackingType == "plyo" {
            // ponytail: sauts + hauteur/distance. repsStr = vrais reps CSV (case
            // "reps","plyo" groupé L207). intensity per-set dans sets_json —
            // unité native de l'exo (cm/m), pas de conversion. Pas d'agrégation
            // top-level (v1 b') ; colonne exercise_logs.intensity reste NULL
            // jusqu'à ce qu'une analytics la peuple depuis sets_json.
            let units = UnitSettings.shared
            let setsPayload: [[String: Any]] = sets.compactMap { s -> [String: Any]? in
                guard (Int(s.reps) ?? 0) > 0 else { return nil }
                let intVal = Double(s.intensity.replacingOccurrences(of: ",", with: ".")) ?? 0
                guard intVal > 0 else { return nil }
                let sw = Double(s.weight.replacingOccurrences(of: ",", with: ".")) ?? 0
                let setTotal = totalWeight(for: units.toStorage(sw))
                return ["weight": setTotal, "reps": s.reps, "intensity": intVal]
            }
            let firstW = setsPayload.compactMap { $0["weight"] as? Double }.first(where: { $0 > 0 }) ?? 0
            let result = ExerciseLogResult(name: name, weight: firstW, reps: repsStr, rpe: exerciseRPE,
                sets: setsPayload, isSecond: isSecondSession, isBonus: isBonusSession,
                equipmentType: equipmentType, painZone: painZone, notes: noteForResult)
            logStatus = .success(firstW)
            return withReconstructionMetadata(result)
        }

        if isTimeBased {
            let setsPayload: [[String: Any]] = sets.map { s -> [String: Any] in
                if isUnilateral {
                    let l = s.durationLeft ?? 0
                    let r = s.durationRight ?? 0
                    return ["weight": 0, "reps": String(l + r),
                            "left": ["time": l], "right": ["time": r]]
                } else {
                    return ["weight": 0, "reps": String(s.duration)]
                }
            }
            let result = ExerciseLogResult(name: name, weight: 0, reps: repsStr, rpe: exerciseRPE,
                sets: setsPayload, isSecond: isSecondSession, isBonus: isBonusSession,
                equipmentType: "bodyweight", painZone: painZone, notes: noteForResult)
            logStatus = .success(0)
            return withReconstructionMetadata(result)
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
            equipmentType: equipmentType, painZone: painZone, notes: noteForResult)
        logStatus = .success(total)
        return withReconstructionMetadata(result)
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
    var hasTimingContext: Bool { startTime != nil }

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
    enum RecoveryAdmission: Equatable {
        // Caller attestation only; this does NOT prove program/fingerprint provenance.
        case allowCurrentScopedRecovery, deny
    }
    enum PreparationError: Error {
        case invalidContext, ownerNotFresh, alreadyPrepared, contextChanged, finalizationDisabled
    }
    private struct LocalExecutionContext: Equatable {
        let token: String
        let date: String
        let source: String
        let session: String
    }
    private var localExecutionContext: LocalExecutionContext?
    private var localRecoveryAdmitted = false
    private var preparingLocalExecution = false
    var isDayComposerLocal: Bool { localExecutionContext != nil }

    /// No fetch, server synthesis, timing, cleanup or persistence during preparation.
    /// Admission must be supplied by a caller that has independently validated provenance.
    /// Even an identical second preparation is rejected without changing the owner.
    func prepareForDayComposer(data: SeanceData, sessionDate: String, source: String,
                               sessionName: String, contextToken: String,
                               recoveryAdmission: RecoveryAdmission) throws {
        guard ["morning", "evening"].contains(source), source == draftSessionType,
              !sessionDate.isEmpty, data.todayDate == sessionDate,
              !sessionName.isEmpty, data.today == sessionName, !contextToken.isEmpty else {
            throw PreparationError.invalidContext
        }
        let context = LocalExecutionContext(token: contextToken, date: sessionDate,
                                            source: source, session: sessionName)
        if let existing = localExecutionContext {
            throw existing == context ? PreparationError.alreadyPrepared : PreparationError.contextChanged
        }
        guard seanceData == nil, logResults.isEmpty, sessionComment.isEmpty,
              !sessionStarted, !chrono.hasTimingContext, !isLoading, !isFinishing, !showSuccess,
              !isResuming, !partialSaveAccepted, retryFinishAction == nil,
              finishExerciseSaves.isEmpty, finishSaveScope == nil, finishSourceDate == nil else {
            throw PreparationError.ownerNotFresh
        }

        localExecutionContext = context
        localRecoveryAdmitted = recoveryAdmission == .allowCurrentScopedRecovery
        preparingLocalExecution = true
        restoringProtectedLogs = true
        defer { preparingLocalExecution = false; restoringProtectedLogs = false }
        seanceData = data // Existing comment restoration is read-only and admission-gated.
        if localRecoveryAdmitted {
            logResults = localRecovery(date: sessionDate)
            isResuming = !logResults.isEmpty
        }
    }

    private func rejectLocalFinalization() -> Bool {
        guard isDayComposerLocal else { return false }
        submitError = "Finalisation indisponible pour cette préparation locale."
        return true
    }

    @Published var seanceData: SeanceData? {
        didSet {
            if isDayComposerLocal && !preparingLocalExecution {
                seanceData = oldValue // The injected DTO/date cannot be replaced by a reload.
                return
            }
            restoreSessionComment()
        }
    }
    private var restoringSessionComment = false
    @Published var sessionComment = "" {
        didSet {
            if isDayComposerLocal && !localRecoveryAdmitted {
                sessionComment = oldValue
                return
            }
            guard !restoringSessionComment, let date = seanceData?.todayDate else { return }
            SessionDraftStore.saveComment(sessionComment, date: date, sessionType: draftSessionType)
        }
    }

    /// Hydration/full-clear refresh is not an edit and must not create recovery metadata.
    func restoreSessionComment() {
        guard !isDayComposerLocal || localRecoveryAdmitted else { return }
        restoringSessionComment = true
        defer { restoringSessionComment = false }
        sessionComment = seanceData.flatMap {
            SessionDraftStore.loadComment(date: $0.todayDate, sessionType: draftSessionType)
        } ?? ""
    }
    @Published var isLoading = false
    @Published var error: String?
    private var restoringProtectedLogs = false
    @Published var logResults: [String: ExerciseLogResult] = [:] {
        didSet {
            if isDayComposerLocal && !localRecoveryAdmitted {
                logResults = oldValue
                return
            }
            persistDraftIfNeeded()
        }
    }
    @Published var showSuccess = false {
        didSet {
            if isDayComposerLocal { showSuccess = false; return }
            if showSuccess {
                finishExerciseSaves.removeAll()
                retryFinishAction = nil
                failedExerciseNames = []
                NotificationCenter.default.post(name: .sessionCompleted, object: nil)
            }
        }
    }
    @Published var submitError: String?
    @Published var isResuming = false
    @Published var commitWarning: String?
    @Published var commitWarningStyle: ToastStyle = .error
    // private(set) retiré : les overrides finish() des sous-classes
    // (SeanceSoirViewModel, BonusSeanceViewModel) doivent pouvoir set le
    // guard de double-submit symétrique au parent.
    @Published var isFinishing = false
    @Published var prCelebrations: [(name: String, oneRM: Double)] = []
    @Published private(set) var failedExerciseNames: [String] = []
    private struct FinishExerciseSave {
        enum State { case accepted, failed }
        let payload: ExerciseLogResult
        let fingerprint: Data
        let state: State
    }
    private var finishExerciseSaves: [String: FinishExerciseSave] = [:]
    private var finishSaveScope: String?
    // Frozen before the first await. Never derive a queued payload's date from the clock.
    private(set) var finishSourceDate: String?
    private var retryFinishAction: ((String) async -> Void)?
    var canRetryFinish: Bool { retryFinishAction != nil }
    private(set) var partialSaveAccepted = false

    func prepareFinishRetry(rpe: Double, comment: String, durationMin: Double?, energyPre: Int?,
                            sessionName: String?, bonusSession: Bool, closeSession: Bool) {
        guard !rejectLocalFinalization() else { return }
        submitError = nil
        partialSaveAccepted = false
        let retryDate = seanceData?.todayDate
        let requiresSourceDate = draftSessionType == "morning" || draftSessionType == "evening"
        retryFinishAction = { [weak self] currentComment in
            guard !requiresSourceDate || self?.seanceData?.todayDate == retryDate else {
                self?.submitError = "Le contexte de séance a changé. Les données locales sont conservées."
                return
            }
            await self?.finish(rpe: rpe, comment: currentComment, durationMin: durationMin,
                               energyPre: energyPre, sessionName: sessionName,
                               bonusSession: bonusSession, closeSession: closeSession)
        }
    }

    func retryFinish(comment: String) async {
        guard !rejectLocalFinalization() else { return }
        guard !isFinishing else { return }
        await retryFinishAction?(comment)
    }

    func acceptPartialSave() { partialSaveAccepted = true }

    // Overridable network boundary for targeted tests, using the explicit g2a contract.
    func sendExerciseForFinish(_ result: ExerciseLogResult) async throws -> ExerciseSaveOutcome {
        guard !isDayComposerLocal else { throw PreparationError.finalizationDisabled }
        return try await APIService.shared.logExerciseOutcome(
            exercise: result.name, weight: result.weight, reps: result.reps, rpe: result.rpe,
            sets: result.sets, force: true, isSecond: result.isSecond, isBonus: result.isBonus,
            equipmentType: result.equipmentType, painZone: result.painZone, notes: result.notes,
            date: draftSessionType == "bonus" ? nil : finishSourceDate, invalidate: false)
    }

    func sendMorningSession(exos: [String], rpe: Double, comment: String, date: String,
                            durationMin: Double?, energyPre: Int?, sessionName: String?,
                            exerciseLogs: [[String: Any]]) async throws -> SessionSaveOutcome {
        guard !isDayComposerLocal else { throw PreparationError.finalizationDisabled }
        return try await APIService.shared.logMorningSessionOutcome(exos: exos, rpe: rpe, comment: comment,
            date: date, durationMin: durationMin, energyPre: energyPre, sessionName: sessionName,
            exerciseLogs: exerciseLogs)
    }

    private func finishFingerprint(_ result: ExerciseLogResult) throws -> Data {
        var fields: [String: Any] = ["name": result.name, "weight": result.weight, "reps": result.reps,
            "sets": result.sets, "isSecond": result.isSecond, "isBonus": result.isBonus,
            "equipmentType": result.equipmentType, "painZone": result.painZone, "notes": result.notes]
        if let rpe = result.rpe { fields["rpe"] = rpe }
        return try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
    }

    /// No persistent success IDs: after recreation all restored logs can be safely upserted again.
    func saveExercisesForFinish(isSecond: Bool? = nil, isBonus: Bool? = nil, collectPRs: Bool = true) async -> Bool {
        guard !rejectLocalFinalization() else { return false }
        submitError = nil
        finishSourceDate = seanceData?.todayDate
        if draftSessionType != "bonus", finishSourceDate?.isEmpty != false {
            submitError = "Date de séance indisponible. Les données locales sont conservées."
            return false
        }
        let scope = "\(draftSessionType)/\(seanceData?.todayDate ?? "")"
        if finishSaveScope != scope { finishExerciseSaves.removeAll(); finishSaveScope = scope }
        let snapshot = logResults
        finishExerciseSaves = finishExerciseSaves.filter { snapshot[$0.key] != nil }
        var failures: [String] = []
        var invalidations: [CacheInvalidation] = []
        for key in snapshot.keys.sorted() {
            guard var result = snapshot[key] else { continue }
            if let isSecond { result.isSecond = isSecond }
            if let isBonus { result.isBonus = isBonus }
            do {
                let fingerprint = try finishFingerprint(result)
                if let saved = finishExerciseSaves[key], saved.fingerprint == fingerprint,
                   case .accepted = saved.state { continue }
                do {
                    let outcome = try await sendExerciseForFinish(result)
                    switch outcome {
                    case .confirmed(let response):
                        invalidations.append(.exerciseLogged(isSecond: result.isSecond, isBonus: result.isBonus))
                        if collectPRs, response.isPR == true {
                            prCelebrations.append((name: result.name, oneRM: response.oneRM ?? 0))
                        }
                    case .queuedOffline: break
                    }
                    finishExerciseSaves[key] = FinishExerciseSave(payload: result, fingerprint: fingerprint, state: .accepted)
                } catch {
                    finishExerciseSaves[key] = FinishExerciseSave(payload: result, fingerprint: fingerprint, state: .failed)
                    throw error
                }
            } catch { failures.append(result.name) }
        }
        CacheInvalidation.invalidateBatch(invalidations)
        guard draftSessionType == "bonus" || seanceData?.todayDate == finishSourceDate else {
            submitError = "Le contexte de séance a changé. Les données locales sont conservées."
            return false
        }
        // A change made while awaiting the network must be saved before finalization too.
        for key in snapshot.keys where logResults[key] == nil {
            failures.append(snapshot[key]?.name ?? key)
        }
        for (key, current) in logResults {
            var result = current
            if let isSecond { result.isSecond = isSecond }
            if let isBonus { result.isBonus = isBonus }
            if let saved = finishExerciseSaves[key], case .accepted = saved.state,
               let fingerprint = try? finishFingerprint(result), saved.fingerprint == fingerprint { continue }
            failures.append(result.name)
        }
        failedExerciseNames = Array(Set(failures)).sorted()
        guard failedExerciseNames.isEmpty else {
            submitError = "Ta séance reste disponible sur cet appareil. Réessaie pour terminer la sauvegarde.\n\n" + failedExerciseNames.joined(separator: ", ")
            return false
        }
        return true
    }

    var sessionStart = Date()
    @Published private(set) var sessionStarted = false
    var draftSessionType: String {
        didSet { if let context = localExecutionContext { draftSessionType = context.source } }
    }
    let chrono = WorkoutChronoViewModel()

    var cacheService: CacheService = .shared

    // Init obligatoire (2026-07-20) : retirer le default "morning" élimine le
    // piège permanent d'un futur écran qui ferait `SeanceViewModel()` en pensant
    // « peu importe le type » depuis un contexte soir. Les sous-classes (bonus,
    // evening) gardent leur propre override avec le bon default — le default
    // parent n'était utilisé qu'en instanciation directe.
    init(draftSessionType: String) {
        self.draftSessionType = draftSessionType
    }

    func load() async {
        guard !isDayComposerLocal else { return }
        if seanceData == nil,
           let cached = cacheService.load(for: "seance_data"),
           let decoded = try? APIService.decoder.decode(SeanceData.self, from: cached) {
            seanceData = decoded
            restoreLogResults(from: decoded, serverSessionType: "morning", serverCompleted: decoded.alreadyLogged)
            // Étape 3b — reconcile moot : le backend est autoritative sur les overrides.
        }

        if seanceData == nil { isLoading = true }
        error = nil
        do {
            let fresh = try await APIService.shared.fetchSeanceData()
            seanceData = fresh
            restoreLogResults(from: fresh, serverSessionType: "morning", serverCompleted: fresh.alreadyLogged)
        } catch {
            if seanceData == nil { self.error = error.localizedDescription }
        }
        isLoading = false
    }

    /// Completion must describe the source session, not merely the existence of a log.
    /// Unknown completion preserves the draft; callers must supply the source context.
    func restoreLogResults(from data: SeanceData, serverSessionType: String, serverCompleted: Bool?) {
        guard !isDayComposerLocal else { return }
        // Restoration is not an edit, including legacy/undecodable recovery state.
        restoringProtectedLogs = SessionDraftStore.protectsRecovery(sessionType: draftSessionType)
        defer { restoringProtectedLogs = false }
        let program = data.fullProgram[data.today] ?? [:]
        var restored: [String: ExerciseLogResult] = [:]
        // Restauration depuis l'historique serveur : UNIQUEMENT en session matin.
        // En séance 2 (evening) ou bonus, les exos du matin ne doivent PAS remonter
        // dans logResults — sinon finish() les ré-poste vides sur la nouvelle session
        // (Crime 4 racine : rows placeholder sets_json=[] avec agrégats matin,
        // 16+ dates polluées prouvées au SQL Vince 2026-07-13). Le draft local
        // ci-dessous reste actif pour toutes les sous-classes (scoped par
        // sessionType via Volet C).
        //
        // Contamination inverse (2026-07-20) : le tri backend history est
        // (date DESC, len(sets) DESC) — indistinct matin/soir. Si un exo est
        // loggué matin ET soir le même jour, .first peut être la row soir plus
        // riche. En restore matin, on restituerait alors un log soir sous la clé
        // matin. Le filtre `sessionType == "morning"` bloque ça — les vieux logs
        // sans session_type (backward-compat) matchent aussi car défaut morning.
        if draftSessionType == "morning" {
            for exerciseName in program.keys {
                if let first = data.weights[exerciseName]?.history?.first(where: {
                        $0.date == data.todayDate && ($0.sessionType ?? "morning") == "morning"
                   }),
                   let w = first.weight, let r = first.reps {
                    restored[exerciseName] = ExerciseLogResult(name: exerciseName, weight: w, reps: r)
                }
            }
        }
        restored.merge(localRecovery(date: data.todayDate)) { _, local in local }
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
        if serverSessionType == draftSessionType, serverCompleted == true,
           SessionDraftStore.isAutomaticCleanupAllowed(date: data.todayDate, sessionType: draftSessionType) {
            SessionDraftStore.clear(date: data.todayDate, sessionType: draftSessionType)
        }
    }

    /// Preserve all local entries, including names outside the injected plan.
    private func localRecovery(date: String) -> [String: ExerciseLogResult] {
        var restored: [String: ExerciseLogResult] = [:]
        for pending in SessionDraftStore.load(date: date, sessionType: draftSessionType) {
            let restoredSets = pending.sets.map(\.payload)
            restored[pending.name] = ExerciseLogResult(
                name: pending.name,
                weight: pending.weight,
                reps: pending.reps,
                rpe: pending.rpe,
                sets: restoredSets,
                isSecond: pending.isSecond,
                isBonus: pending.isBonus,
                equipmentType: pending.equipmentType,
                painZone: pending.painZone,
                notes: pending.notes ?? "",
                trackingType: pending.trackingType,
                scheme: pending.scheme,
                isUnilateral: pending.isUnilateral
            )
        }
        return restored
    }

    // Extra overrides the status source, never the common save gate/retry pipeline.
    // Completion describes server status, not acknowledgment of the local generation.
    func verifyFinishCompletion() async -> Bool {
        guard !isDayComposerLocal else { return false }
        guard draftSessionType != "bonus" else { return false }
        return (try? await APIService.shared.fetchSeanceData().alreadyLogged) == true
    }

    func handleFinishConflict() -> Bool {
        guard !rejectLocalFinalization() else { return false }
        guard draftSessionType != "bonus" else {
            submitError = "La séance existe déjà. Les données locales sont conservées ; leur synchronisation n’est pas confirmée."
            return false
        }
        if let date = seanceData?.todayDate {
            guard SessionDraftStore.isAutomaticCleanupAllowed(date: date, sessionType: draftSessionType) else {
                submitError = "La séance existe déjà. Les données locales sont conservées ; leur synchronisation n’est pas confirmée."
                return false
            }
            SessionDraftStore.clear(date: date, sessionType: draftSessionType)
        }
        commitWarning = "Séance déjà marquée terminée côté serveur."
        commitWarningStyle = .success
        return true
    }

    /// Shared completion branch: server status alone never retires protected recovery.
    func applyCompletedSessionRecoveryPolicy() {
        guard !isDayComposerLocal else { return }
        guard let date = seanceData?.todayDate else { return }
        if SessionDraftStore.isAutomaticCleanupAllowed(date: date, sessionType: draftSessionType) {
            SessionDraftStore.clear(date: date, sessionType: draftSessionType)
        } else {
            commitWarning = "Séance complétée côté serveur. Les données locales sont conservées ; leur synchronisation n’est pas confirmée."
            commitWarningStyle = .success
        }
    }

    // closeSession : knob PM-only honoré par SeanceSoirViewModel.finish
    // (branche "Reprendre plus tard" = persist exos sans écrire completed=True).
    // Ignoré ici : AM/bonus ferment toujours.
    func finish(rpe: Double, comment: String, durationMin: Double? = nil, energyPre: Int? = nil, sessionName: String? = nil, bonusSession: Bool = false, closeSession: Bool = true) async {
        guard !rejectLocalFinalization() else { return }
        guard !isFinishing else { return }
        isFinishing = true
        prepareFinishRetry(rpe: rpe, comment: comment, durationMin: durationMin, energyPre: energyPre,
                           sessionName: sessionName, bonusSession: bonusSession, closeSession: closeSession)

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
        guard await saveExercisesForFinish() else { return }
        let date = finishSourceDate
        let isMorning = draftSessionType == "morning" && !bonusSession

        do {
            if isMorning, let date {
                let outcome = try await sendMorningSession(exos: exos, rpe: rpe, comment: comment,
                    date: date, durationMin: durationMin, energyPre: energyPre,
                    sessionName: sessionName, exerciseLogs: exerciseLogs)
                if case .queuedOffline = outcome {
                    submitError = "Synchronisation en attente. Données conservées sur cet appareil."
                    return
                }
            } else {
                try await APIService.shared.logSession(exos: exos, rpe: rpe, comment: comment,
                                                       durationMin: durationMin, energyPre: energyPre,
                                                       bonusSession: bonusSession, sessionName: sessionName,
                                                       exerciseLogs: exerciseLogs)
            }
        } catch APIError.serverError(409, _) {
            if isMorning {
                submitError = "La tentative n’est pas confirmée. Les données locales sont conservées."
                return
            }
            let confirmed = handleFinishConflict()
            await APIService.shared.fetchDashboard()
            if confirmed { showSuccess = true }
            return
        } catch {
            submitError = "Erreur lors de l'enregistrement : \(error.localizedDescription)"
            // Draft conservé intentionnellement : les données restent restaurables au redémarrage.
            // Une completion observée plus tard n'acquitte pas ces données locales.
            await APIService.shared.fetchDashboard()
            return
        }

        // seance_data is today-only. Fail closed across midnight rather than
        // accepting completion of another date; no claim of historical verification.
        let verified: Bool
        if isMorning {
            let fresh = try? await APIService.shared.fetchSeanceData()
            verified = fresh?.todayDate == date && fresh?.alreadyLogged == true
                && seanceData?.todayDate == date
        } else {
            verified = await verifyFinishCompletion()
        }

        await APIService.shared.fetchDashboard()
        if !verified || (isMorning && seanceData?.todayDate != date) {
            submitError = "Séance non confirmée en base — vérifie ta connexion et réessaie."
        } else {
            applyCompletedSessionRecoveryPolicy()
            BehaviorTracker.shared.record(.sessionEnd)
            await HealthKitService.shared.saveStrengthWorkout(startDate: sessionStart, endDate: Date())
            showSuccess = true
        }
    }

    func startSession() {
        guard !isDayComposerLocal else { return }
        guard !sessionStarted else { return }
        sessionStart = Date()
        sessionStarted = true
        if let date = seanceData?.todayDate {
            SessionDraftStore.saveStartedAt(date: date, sessionType: draftSessionType, startedAt: sessionStart)
            chrono.start(date: date, sessionType: draftSessionType)
        }
    }

    private func persistDraftIfNeeded() {
        guard !restoringProtectedLogs else { return }
        guard let date = seanceData?.todayDate else { return }
        if logResults.isEmpty {
            if isDayComposerLocal {
                // An explicit local undo is an edit, not permission to erase timing metadata.
                SessionDraftStore.save(date: date, sessionType: draftSessionType, values: [])
            } else {
                SessionDraftStore.clearLogs(date: date, sessionType: draftSessionType)
            }
            sessionStarted = false
            return
        }
        if !isDayComposerLocal && !sessionStarted {
            sessionStart = Date()
            sessionStarted = true
            SessionDraftStore.saveStartedAt(date: date, sessionType: draftSessionType, startedAt: sessionStart)
            chrono.start(date: date, sessionType: draftSessionType)
        }
        let values = logResults.values.map { log in
            PersistedExerciseLogResult(
                name: log.name,
                weight: log.weight,
                reps: log.reps,
                rpe: log.rpe,
                isSecond: log.isSecond,
                isBonus: log.isBonus,
                equipmentType: log.equipmentType,
                painZone: log.painZone,
                sets: log.sets.compactMap { s in
                    PersistedSet.preserving(s, trackingType: log.trackingType ?? seanceData?.inventoryTracking[log.name] ?? "reps")
                },
                trackingType: log.trackingType,
                notes: log.notes,
                scheme: log.scheme,
                isUnilateral: log.isUnilateral
            )
        }
        SessionDraftStore.save(date: date, sessionType: draftSessionType, values: values)
        if !isDayComposerLocal {
            SessionDraftStore.saveStartedAt(date: date, sessionType: draftSessionType, startedAt: sessionStart)
        }
    }
}
