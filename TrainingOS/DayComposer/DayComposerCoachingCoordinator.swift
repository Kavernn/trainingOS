import Foundation
import Combine

/// Navigation only. Finalization evidence, progression rules, Apply and replay
/// remain owned by their existing R11.0 contracts.
@MainActor
final class DayComposerCoachingCoordinator: ObservableObject {
    let flow = ProgressionFlow()
    let context: DayComposerExecutionContext
    @Published private(set) var contextRejected = false
    @Published private(set) var activeSource: DayComposerSource?
    @Published private(set) var required: [DayComposerSource: ProgressionContext] = [:]
    @Published private(set) var resolved: Set<DayComposerSource> = []
    private var order: [DayComposerSource] = []
    private let defaults: UserDefaults
    private let ownerIsValid: () -> Bool
    private var mounted = true
    private var generation = 0

    init(context: DayComposerExecutionContext, defaults: UserDefaults = .standard,
         ownerIsValid: @escaping () -> Bool) {
        self.context = context
        self.defaults = defaults
        self.ownerIsValid = ownerIsValid
    }

    var allResolved: Bool { required.keys.allSatisfy { resolved.contains($0) } }

    /// Only durable business-confirmed finalization plus completion observation
    /// can admit a source. Pending/unverified/failed cannot request Coaching.
    func observe(_ state: DayComposerSourceFinishState?) {
        guard let state, state.isResolved, state.finalOperation.application == .confirmed,
              state.identity.date == context.date,
              state.identity.activeProgramID == context.activeProgramID,
              state.identity.sourceFingerprint == context.sourceFingerprint,
              state.identity.morningSession == context.morningSession,
              state.identity.eveningSession == context.eveningSession,
              DayComposerFinalizationCoding.isDate(context.date), ownerIsValid() else { return }
        let source = state.source
        let name = source == .morning ? context.morningSession : context.eveningSession
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let value = ProgressionContext(date: context.date, sessionType: source.rawValue, sessionName: name)
        guard required[source] == nil else { return }
        required[source] = value
        if defaults.bool(forKey: marker(value)) { resolved.insert(source) }
        else { order.append(source) }
        presentNext()
    }

    /// A completed source may receive a new prescription through Coaching.
    /// Freeze only its scheme for the current execution identity; date/programme,
    /// names, IDs, order, groups, tracking and unfinished prescriptions still
    /// have to match. A fresh completion observation is mandatory.
    static func snapshotForFinalization(_ current: DayComposerSnapshot,
        completedPlans: [DayComposerSource: DayComposerPlan]) -> DayComposerSnapshot {
        func plan(_ actual: DayComposerPlan, completed: Bool) -> DayComposerPlan {
            guard completed, let original = completedPlans[actual.source],
                  original.source == actual.source, original.session == actual.session,
                  original.units.count == actual.units.count else { return actual }
            for (a, b) in zip(original.units, actual.units) {
                guard a.group == b.group, a.rest == b.rest, a.items.count == b.items.count else { return actual }
                for (x, y) in zip(a.items, b.items) {
                    guard x.id == y.id, x.name == y.name, x.sourceOrder == y.sourceOrder,
                          x.tracking == y.tracking, x.unilateral == y.unilateral else { return actual }
                }
            }
            return original
        }
        return .init(date: current.date, activeProgramID: current.activeProgramID,
            morning: plan(current.morning, completed: current.morningCompleted),
            evening: plan(current.evening, completed: current.eveningCompleted),
            morningCompleted: current.morningCompleted, eveningCompleted: current.eveningCompleted)
    }

    private func marker(_ value: ProgressionContext) -> String {
        // One local decision marker per date/source/canonical session.
        // No workout evidence or Apply status is stored here.
        "dc-coaching-resolved-v1-" + Data(value.identity.utf8).base64EncodedString()
    }

    private func presentNext() {
        guard mounted, !contextRejected, ownerIsValid(), activeSource == nil,
              let source = order.first(where: { !resolved.contains($0) }),
              let value = required[source] else { return }
        activeSource = source
        flow.begin(value) { [weak self] in self?.resolve(source, context: value) }
    }

    private func resolve(_ source: DayComposerSource, context value: ProgressionContext) {
        guard mounted, ownerIsValid(), activeSource == source, required[source] == value else { return }
        defaults.set(true, forKey: marker(value))
        resolved.insert(source)
        activeSource = nil
        presentNext()
    }

    /// Called only after recap dismissal, or an explicit retry. ProgressionFlow
    /// enforces one in-flight fetch and rejects stale generations.
    func fetch(using read: @escaping (ProgressionContext) async -> ProgressionFetchOutcome) async {
        guard mounted, !contextRejected, ownerIsValid(), let source = activeSource,
              let value = required[source], flow.context == value else { return }
        let token = generation
        await flow.fetch { [weak self] requested in
            let result = await read(requested)
            guard let self, self.generation == token, self.mounted, self.ownerIsValid(),
                  self.activeSource == source, self.required[source] == requested else {
                return .failed(.staleContext)
            }
            switch result {
            case .actionable(let rows), .maintainOnly(let rows):
                guard rows.allSatisfy({ $0.programID == self.context.activeProgramID }) else {
                    self.contextRejected = true
                    self.suspend()
                    return .failed(.staleContext)
                }
            default: break
            }
            return result
        }
        guard generation == token else { return }
        if !ownerIsValid() { suspend() }
        else if mounted, activeSource == source, flow.context == value,
                flow.phase == .failed(.cancelled) || flow.phase == .failed(.staleContext) {
            // A normal cancellation offers the recap again, never a silent
            // unresolved failure with no way forward.
            suspend()
            resume()
        }
    }

    func finishDecision(for source: DayComposerSource? = nil) {
        if let source, source != activeSource { return }
        flow.finish()
    }

    func suspend() {
        generation += 1
        mounted = false
        flow.invalidate()
        activeSource = nil
    }

    func resume() {
        guard !contextRejected, ownerIsValid() else { suspend(); return }
        if !mounted {
            order = [.morning, .evening].filter { required[$0] != nil }
        }
        mounted = true
        presentNext()
    }
}
