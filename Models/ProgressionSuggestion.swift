import Foundation
import Combine

struct ProgressionSuggestion: Codable, Identifiable {
    var id: String { exerciseName }

    let exerciseName: String
    let loadProfile: String?
    let suggestionType: String   // "increase_weight" | "increase_sets" | "deload" | "maintain" | "regression" | "rep_progress"
    let currentWeight: Double?
    let suggestedWeight: Double?
    let currentScheme: String?
    let suggestedScheme: String?
    let reason: String
    let fatigueWarning: Bool

    var expectedCurrentWeight: Double? = nil
    var expectedCurrentScheme: String? = nil
    var programID: String? = nil
    var referenceAvailable: Bool? = nil

    var canApply: Bool {
        referenceAvailable == true && programID != nil && suggestionType != "maintain" && suggestionType != "rep_progress" &&
        ((suggestedWeight != nil && suggestedWeight != expectedCurrentWeight) ||
         (suggestedScheme != nil && suggestedScheme != expectedCurrentScheme))
    }
    var identity: String {
        [exerciseName, suggestionType, String(describing: expectedCurrentWeight), expectedCurrentScheme ?? "",
         String(describing: suggestedWeight), suggestedScheme ?? "", programID ?? ""].joined(separator: "\u{1f}")
    }

    enum CodingKeys: String, CodingKey {
        case expectedCurrentWeight = "expected_current_weight"
        case expectedCurrentScheme = "expected_current_scheme"
        case programID = "program_id"
        case referenceAvailable = "reference_available"
        case exerciseName    = "exercise_name"
        case loadProfile     = "load_profile"
        case suggestionType  = "suggestion_type"
        case currentWeight   = "current_weight"
        case suggestedWeight = "suggested_weight"
        case currentScheme   = "current_scheme"
        case suggestedScheme = "suggested_scheme"
        case reason
        case fatigueWarning  = "fatigue_warning"
    }
}

struct ProgressionSuggestionsResponse: Codable {
    let suggestions: [ProgressionSuggestion]
}

struct ProgressionContext: Equatable, Hashable {
    let date: String
    let sessionType: String
    let sessionName: String
    static func sessionType(second: Bool, bonus: Bool) -> String { bonus ? "bonus" : (second ? "evening" : "morning") }
    var identity: String { [date, sessionType, sessionName].joined(separator: "\u{1f}") }
    func ignoreKey(for suggestion: ProgressionSuggestion) -> String {
        "prog_ignore_v2_" + Data((identity + "\u{1f}" + suggestion.identity).utf8).base64EncodedString()
    }
}

enum ProgressionFetchFailure: Equatable {
    case http(Int), decoding, network, cancelled, staleContext
    var message: String {
        switch self {
        case .http(let code): return "Coaching indisponible (HTTP \(code)). Tu peux réessayer ou terminer."
        case .decoding: return "Réponse Coaching invalide. Tu peux réessayer ou terminer."
        case .network: return "Connexion au Coaching impossible. Tu peux réessayer ou terminer."
        case .cancelled, .staleContext: return "Chargement du Coaching interrompu."
        }
    }
}

enum ProgressionFetchOutcome {
    case actionable([ProgressionSuggestion]), maintainOnly([ProgressionSuggestion]), none
    case failed(ProgressionFetchFailure)
    static func decode(_ data: Data, status: Int) -> Self {
        guard (200..<300).contains(status) else { return .failed(.http(status)) }
        do {
            let rows = try JSONDecoder().decode(ProgressionSuggestionsResponse.self, from: data).suggestions
            if rows.isEmpty { return .none }
            return rows.contains { $0.suggestionType != "maintain" } ? .actionable(rows) : .maintainOnly(rows)
        } catch { return .failed(.decoding) }
    }
}

/// Only successful non-actionable outcomes; an empty response carries no cause.
enum ProgressionResultFeedback: Equatable {
    case maintain, none
    var message: String {
        switch self {
        case .maintain: return "Maintien recommandé"
        case .none: return "Aucun ajustement recommandé"
        }
    }
    var announcement: String { "Coaching analysé · \(message)" }
}

/// Local to one workout owner; no global navigation state.
@MainActor final class ProgressionFlow: ObservableObject {
    enum Phase: Equatable { case idle, recap, loading, coaching, failed(ProgressionFetchFailure), finished }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var suggestions: [ProgressionSuggestion] = []
    private(set) var context: ProgressionContext?
    private var generation = 0
    private var valid = true
    private var task: Task<ProgressionFetchOutcome, Never>?
    private var completion: (() -> Void)?
    private var resultFeedback: (@MainActor (ProgressionResultFeedback) -> Void)?

    func begin(_ context: ProgressionContext,
               onFeedback: @escaping @MainActor (ProgressionResultFeedback) -> Void = {
                   ActionFeedbackManager.shared.showCoachingResult($0)
               }, onFinish: @escaping () -> Void) {
        task?.cancel(); generation += 1; valid = true
        resultFeedback = onFeedback
        self.context = context; completion = onFinish; suggestions = []; phase = .recap
    }
    func fetch(using read: @escaping (ProgressionContext) async -> ProgressionFetchOutcome) async {
        guard valid, let context, phase == .recap || isFailure else { return }
        let token = generation
        phase = .loading
        let work = Task { await read(context) }
        // Retain a cancellation handle without turning cancellation into an empty result.
        task = work
        let outcome = await withTaskCancellationHandler(operation: { await work.value }, onCancel: { work.cancel() })
        guard valid, generation == token, self.context == context else { return }
        guard !Task.isCancelled, !work.isCancelled else { phase = .failed(.cancelled); return }
        switch outcome {
        case .actionable(let rows): suggestions = rows; phase = .coaching
        case .maintainOnly: resultFeedback?(.maintain); finish()
        case .none: resultFeedback?(.none); finish()
        case .failed(let error): phase = .failed(error)
        }
    }
    var isFailure: Bool { if case .failed = phase { return true }; return false }
    func finish() {
        guard valid, phase != .finished else { return }
        phase = .finished
        resultFeedback = nil
        let callback = completion; completion = nil; callback?()
    }
    func invalidate() { valid = false; generation += 1; task?.cancel(); task = nil; completion = nil; resultFeedback = nil }
    func contextChanged(to value: ProgressionContext) {
        if let context, context != value { invalidate(); phase = .failed(.staleContext) }
    }
}

struct ProgressionApplied: Codable, Equatable {
    let success: Bool
    let currentWeight: Double?
    let currentScheme: String?
    enum CodingKeys: String, CodingKey {
        case success, currentWeight = "current_weight", currentScheme = "current_scheme"
    }
    static func confirmed(_ data: Data, for payload: [String: Any]) -> Self? {
        guard let receipt = confirmed(data) else { return nil }
        let restoring = payload["restore"] as? Bool == true
        let weight = payload["suggested_weight"] as? Double ?? (restoring ? nil : payload["expected_current_weight"] as? Double)
        let scheme = payload["suggested_scheme"] as? String ?? (restoring ? nil : payload["expected_current_scheme"] as? String)
        guard receipt.currentWeight == weight, receipt.currentScheme == scheme else { return nil }
        return receipt
    }
    static func confirmed(_ data: Data) -> Self? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object.keys.contains("current_weight"), object.keys.contains("current_scheme"),
              let value = try? JSONDecoder().decode(Self.self, from: data), value.success,
              value.currentWeight.map({ $0.isFinite && $0 >= 0 }) ?? true else { return nil }
        return value
    }
}

enum ProgressionApplyOutcome: Equatable {
    case confirmed(ProgressionApplied), queued, conflict, failed(String)
    static func response(_ data: Data) -> Self {
        guard let receipt = ProgressionApplied.confirmed(data) else { return .failed("Application non confirmée : réponse invalide.") }
        return .confirmed(receipt)
    }
}

struct ProgressionApplyRequest {
    let context: ProgressionContext
    let exercise: String
    let programID: String
    let weight: Double?
    let scheme: String?
    let expectedWeight: Double?
    let expectedScheme: String?
    var restore = false
    var payload: [String: Any] {
        ["exercise_name": exercise, "program_id": programID, "suggested_weight": weight as Any? ?? NSNull(),
         "suggested_scheme": scheme as Any? ?? NSNull(), "expected_current_weight": expectedWeight as Any? ?? NSNull(),
         "expected_current_scheme": expectedScheme as Any? ?? NSNull(), "session_date": context.date,
         "session_type": context.sessionType, "session_name": context.sessionName, "restore": restore]
    }
    var operationIdentity: String {
        let bytes = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
        return "progression-v1-" + bytes.base64EncodedString()
    }
    func undo(after receipt: ProgressionApplied) -> Self {
        .init(context: context, exercise: exercise, programID: programID, weight: expectedWeight,
              scheme: expectedScheme, expectedWeight: receipt.currentWeight, expectedScheme: receipt.currentScheme, restore: true)
    }
}

@MainActor final class ProgressionRows: ObservableObject {
    enum State: Equatable { case idle, applying, queued, confirmed, restored, conflict, failed(String) }
    @Published private(set) var states: [String: State] = [:]
    private var undoRequests: [String: ProgressionApplyRequest] = [:]
    func state(_ suggestion: ProgressionSuggestion) -> State { states[suggestion.identity] ?? .idle }
    func canUndo(_ suggestion: ProgressionSuggestion) -> Bool {
        guard undoRequests[suggestion.identity] != nil else { return false }
        if state(suggestion) == .confirmed { return true }
        if case .failed = state(suggestion) { return true }
        return false
    }
    func apply(_ suggestion: ProgressionSuggestion, context: ProgressionContext,
               send: (ProgressionApplyRequest) async -> ProgressionApplyOutcome) async {
        guard suggestion.canApply, !canUndo(suggestion), let program = suggestion.programID else { return }
        let request = ProgressionApplyRequest(context: context, exercise: suggestion.exerciseName, programID: program,
            weight: suggestion.suggestedWeight, scheme: suggestion.suggestedScheme == suggestion.expectedCurrentScheme ? nil : suggestion.suggestedScheme,
            expectedWeight: suggestion.expectedCurrentWeight, expectedScheme: suggestion.expectedCurrentScheme)
        await perform(suggestion, request: request, undo: false, send: send)
    }
    func undo(_ suggestion: ProgressionSuggestion, send: (ProgressionApplyRequest) async -> ProgressionApplyOutcome) async {
        guard let request = undoRequests[suggestion.identity] else { return }
        await perform(suggestion, request: request, undo: true, send: send)
    }
    private func perform(_ suggestion: ProgressionSuggestion, request: ProgressionApplyRequest, undo: Bool,
                         send: (ProgressionApplyRequest) async -> ProgressionApplyOutcome) async {
        let key = suggestion.identity
        switch states[key] ?? .idle {
        case .applying, .queued, .conflict, .restored: return
        case .confirmed: if !undo { return }
        default: break
        }
        states[key] = .applying // Set before suspension: same-row double tap is rejected.
        switch await send(request) {
        case .confirmed(let receipt):
            states[key] = undo ? .restored : .confirmed
            undoRequests[key] = undo ? nil : request.undo(after: receipt)
        case .queued: states[key] = .queued
        case .conflict: states[key] = .conflict
        case .failed(let message): states[key] = .failed(message)
        }
    }
}
