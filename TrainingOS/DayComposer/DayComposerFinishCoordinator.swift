import Foundation
import Combine

/// Immutable request artifacts plus an expiring, read-only local-state witness.
/// Reopening requires reconstruction and a fresh stabilization, never deserializing
/// this in-memory capability or treating a historical snapshot as authorization.
@MainActor
struct DayComposerPreparedFinalization {
    let adapter: DayComposerFinalizationRequestAdapter
    let binding: DayComposerFinalInputsCaptureBinding
    fileprivate let capture: DayComposerFinalSourceCapture
    fileprivate let verifyUnchanged: () throws -> Void
    var reference: DayComposerFinalInputsSnapshotReference { binding.snapshotReference }
}

@MainActor
final class DayComposerFinishCoordinator: ObservableObject {
    enum ProductState: Equatable {
        case ready, processing, pending, review, failed, completed
        var title: String {
            switch self {
            case .ready: return "À terminer"
            case .processing: return "Enregistrement en cours…"
            case .pending: return "En attente de synchronisation"
            case .review: return "À vérifier — données conservées"
            case .failed: return "Enregistrement non confirmé"
            case .completed: return "Séance terminée"
            }
        }
        static func from(_ result: Result?) -> Self {
            guard let result else { return .ready }
            if let error = result.error {
                return error == .durabilityFailure ? .failed : .review
            }
            guard let state = result.reconciliation else { return .review }
            if state.isResolved { return .completed }
            if state.hasPending { return .pending }
            if state.finalOperation.application == .failure || state.finalOperation.application == .invalidResponse
                || state.dependencies.items.values.contains(.applicationFailure)
                || state.dependencies.items.values.contains(.invalidResponse) { return .failed }
            if state.requiresReview || state.globalBlock != nil || state.retry == .refreshOnly { return .review }
            return .ready
        }
    }
    enum Phase: Equatable { case idle, reconciling, submittingExercise, submittingFinal, observingCompletion }
    enum Failure: Error, Equatable { case busy, staleSnapshot, contextRejected, durabilityFailure, cancelled }
    enum Action: Equatable { case exercise(OfflineOperationKey), final(OfflineOperationKey), completion }
    struct Result {
        let reconciliation: DayComposerSourceFinishState?
        let actions: [Action]
        let error: Failure?
    }
    @MainActor
    struct Dependencies {
        let server: (DayComposerExecutionIdentity, DayComposerSource) async throws -> DayComposerSourceServerFacts
        let status: (OfflineOperationKey) -> OfflineMutationStatus
        let exercise: (NeutralExerciseSubmissionRequest) async -> NeutralSubmissionOutcome<LogExerciseResponse>
        let final: (NeutralSourceFinalizationRequest) async -> NeutralSubmissionOutcome<LogSessionResponse>
        let completion: (DayComposerSource, String) async -> SourceCompletionObservation

        var serverWithCompletedPlans: ((DayComposerExecutionIdentity, DayComposerSource,
            [DayComposerSource: DayComposerPlan]) async throws -> DayComposerSourceServerFacts)? = nil

        private static func readServer(_ identity: DayComposerExecutionIdentity, _ source: DayComposerSource,
            _ completedPlans: [DayComposerSource: DayComposerPlan]) async throws -> DayComposerSourceServerFacts {
            let bundle = try await DayComposerLoader.loadBundle(program: identity.activeProgramID)
            let projection = try await DayComposerServerProjection.load(date: identity.date)
            let snapshot = DayComposerCoachingCoordinator.snapshotForFinalization(bundle.snapshot, completedPlans: completedPlans)
            guard try DayComposerExecutionIdentity(executionID: identity.executionID,
                context: DayComposerExecutionContext(snapshot: snapshot)) == identity else { throw Failure.contextRejected }
            let items = (source == .morning ? snapshot.morning : snapshot.evening).units.flatMap(\.items)
            let completed = source == .morning ? snapshot.morningCompleted : snapshot.eveningCompleted
            return .init(source: source, date: identity.date, freshness: .fresh,
                observedNames: Set(items.filter { projection.presence(of: $0.name, source: source) == .observed }.map(\.name)),
                completion: completed ? .completedObserved : .notCompleted)
        }

        static var live: Self {
            .init(server: { try await readServer($0, $1, [:]) },
                status: { SyncManager.shared.status(for: $0) },
                exercise: { await APIService.shared.submitExerciseCorrelated($0) },
                final: { await APIService.shared.submitSourceFinalCorrelated($0) },
                completion: { await APIService.shared.observeSourceCompletion(source: $0, date: $1) },
                serverWithCompletedPlans: { try await readServer($0, $1, $2) })
        }
    }

    let coaching: DayComposerCoachingCoordinator

    private weak var execution: DayComposerExecutionCoordinator?
    private let barrier: DayComposerLocalStabilizationBarrier
    private let store: DayComposerFinalizationStore
    private let inputs: DayComposerFinalInputsStore
    private let dependencies: Dependencies
    private var busy: Set<DayComposerSource> = []
    private var refreshingSources = false
    @Published private(set) var phases: [DayComposerSource: Phase] = [:]
    @Published private(set) var productResults: [DayComposerSource: Result] = [:]
    @Published private var preparing: Set<DayComposerSource> = []

    func productState(_ source: DayComposerSource) -> ProductState {
        if preparing.contains(source) || (phases[source] ?? .idle) != .idle { return .processing }
        return .from(productResults[source])
    }
    var dayCompleted: Bool {
        productState(.morning) == .completed && productState(.evening) == .completed && coaching.allResolved
    }

    /// Explicit user command. Every invocation obtains a NEW stabilized capture;
    /// no cached UI artifact survives editing, leaving the screen, or relaunch.
    func finishSource(_ source: DayComposerSource, rpe: Double) async {
        guard preparing.insert(source).inserted else { return }
        defer {
            // Application ACK and completion remain finalization-owned. Coaching
            // is admitted synchronously before processing becomes completed.
            coaching.observe(productResults[source]?.reconciliation)
            preparing.remove(source)
        }
        do {
            guard let execution else { throw Failure.contextRejected }
            try execution.setFinalRPE(rpe, for: source)
            let artifact = try await prepareSource(source)
            let result = await advanceSource(artifact)
            productResults[source] = result
            if result.reconciliation?.isResolved == true {
                NotificationCenter.default.post(name: .sessionCompleted, object: nil)
            }
        } catch {
            productResults[source] = .init(reconciliation: nil, actions: [],
                error: error is DayComposerFinalInputsError ? .durabilityFailure : .staleSnapshot)
        }
    }

    /// Serialize restoration so a faster Evening read cannot present before
    /// Morning. Appearance and foreground may request this same read together.
    func refreshSources() async {
        guard !refreshingSources else { return }
        refreshingSources = true
        defer { refreshingSources = false }
        await refreshSource(.morning)
        guard !Task.isCancelled else { return }
        await refreshSource(.evening)
    }

    /// Reopen/foreground is observation, NEVER an implicit retry/POST. Missing
    /// RPE remains incomplete; no default is written on behalf of the user.
    func refreshSource(_ source: DayComposerSource) async {
        guard !preparing.contains(source), !busy.contains(source), let execution,
              (try? execution.finalInputsParticipant(for: source).prepare()) != nil else { return }
        if let confirmed = productResults[source]?.reconciliation,
           confirmed.isResolved, confirmed.finalOperation.application == .confirmed {
            // Foreground/offline Coaching is not another workout finalization.
            // Keep this owner's durable confirmed completion on network failure.
            guard execution.revalidateExecutionContext() else { return }
            coaching.observe(confirmed)
            return
        }
        preparing.insert(source)
        defer {
            // Application ACK and completion remain finalization-owned. Coaching
            // is admitted synchronously before processing becomes completed.
            coaching.observe(productResults[source]?.reconciliation)
            preparing.remove(source)
        }
        do {
            let artifact = try await prepareSource(source)
            let server = try await readServer(artifact.reference.executionIdentity, source)
            try verify(artifact)
            productResults[source] = .init(reconciliation: try reconcile(artifact, server: server), actions: [], error: nil)
        } catch {
            productResults[source] = .init(reconciliation: nil, actions: [], error: .staleSnapshot)
        }
    }

    init(execution: DayComposerExecutionCoordinator, barrier: DayComposerLocalStabilizationBarrier,
         store: DayComposerFinalizationStore, inputs: DayComposerFinalInputsStore, dependencies: Dependencies) {
        let context = execution.context
        self.coaching = DayComposerCoachingCoordinator(context: context) { [weak execution] in
            guard let execution else { return false }
            return execution.context == context && execution.revalidateExecutionContext()
        }
        self.execution = execution
        self.barrier = barrier
        self.store = store
        self.inputs = inputs
        self.dependencies = dependencies
    }

    private func readServer(_ identity: DayComposerExecutionIdentity,
                            _ source: DayComposerSource) async throws -> DayComposerSourceServerFacts {
        guard let read = dependencies.serverWithCompletedPlans, let execution else {
            return try await dependencies.server(identity, source)
        }
        let original = execution.input.snapshot
        let completed = Dictionary(uniqueKeysWithValues: coaching.required.keys.map {
            ($0, $0 == .morning ? original.morning : original.evening)
        })
        return try await read(identity, source, completed)
    }

    private func history(identity: DayComposerExecutionIdentity, source: DayComposerSource,
                         keys: [OfflineOperationKey] = []) throws -> DayComposerFinalizationHistory {
        let current = try store.load(identity: identity)
        let candidates = try store.candidateRecords(date: identity.date, source: source)
        let records = candidates + (current.map { [$0] } ?? [])
        var all = Set(keys)
        for record in records {
            all.formUnion(record.exerciseIntents.filter { $0.exerciseVersion.source == source }.map(\.operationKey))
            all.formUnion(record.finalIntents.filter { $0.sourceVersion.source == source }.map(\.operationKey))
        }
        var transports: [OfflineOperationKey: DayComposerTransportFact] = [:]
        for key in all { transports[key] = .init(dependencies.status(key)) }
        return .init(durability: .trusted, current: current, candidates: candidates, transports: transports)
    }

    private func input(_ capture: DayComposerFinalSourceCapture, server: DayComposerSourceServerFacts,
                       history: DayComposerFinalizationHistory) -> DayComposerSourceFinalizationInput {
        let local = capture.local
        return .init(identity: local.identity, source: local.source, canonicalPlan: local.canonicalPlan,
            contextFreshness: .fresh, provenanceGuard: local.guardValue, provenanceCompatible: true,
            stabilization: .stableAccepted(local.guardValue), itemFacts: local.itemFacts, comment: local.comment,
            server: server, history: history)
    }

    /// Explicit fresh facts are required; this synchronous method never performs
    /// network work while editors are frozen. Historical snapshots may survive a
    /// failed binding or post-check, but no usable artifact escapes that failure.
    func prepareSource(_ source: DayComposerSource) async throws -> DayComposerPreparedFinalization {
        guard let execution, execution.revalidateExecutionContext() else { throw Failure.contextRejected }
        let identity = execution.finalInputsParticipant(for: source).identity
        let server = try await readServer(identity, source)
        try Task.checkCancellation()
        return try prepareSource(source, server: server)
    }

    func prepareSource(_ source: DayComposerSource, server: DayComposerSourceServerFacts) throws -> DayComposerPreparedFinalization {
        guard let execution, execution.revalidateExecutionContext(), server.source == source,
              server.date == execution.context.date, server.freshness == .fresh else { throw Failure.contextRejected }
        let artifact = try barrier.withStabilizedFinalSource(source) { evidence in
            let rawCapture = try execution.captureFinalSource(for: source, evidence: evidence)
            let capture = try acknowledgingExactHistory(rawCapture, server: server)
            let facts = input(capture, server: server, history: try history(identity: capture.local.identity, source: source))
            let snapshot = try DayComposerFinalizationSnapshot.build(facts).get()
            try store.recordSourceSnapshot(identity: snapshot.identity, version: snapshot.sourceVersion,
                provenanceGuard: snapshot.provenanceGuard)
            guard try store.load(identity: snapshot.identity)?.sourceSnapshots.contains(where: {
                $0.sourceVersion == snapshot.sourceVersion && $0.provenanceGuard == snapshot.provenanceGuard
            }) == true else { throw Failure.durabilityFailure }
            let adapter = try DayComposerFinalizationRequestAdapter(capture: capture, snapshot: snapshot)
            let reference = try DayComposerFinalInputsSnapshotReference(executionIdentity: snapshot.identity, source: source,
                sourceVersion: snapshot.sourceVersion, provenanceGuard: snapshot.provenanceGuard)
            let binding = try inputs.bindCapture(executionIdentity: snapshot.identity, source: source,
                expectedReceipt: capture.finalInputs, snapshotReference: reference, finalPayloadVersion: adapter.finalVersion)
            guard try inputs.verifyCaptureBinding(binding) else { throw Failure.durabilityFailure }
            return DayComposerPreparedFinalization(adapter: adapter, binding: binding,
                capture: capture, verifyUnchanged: evidence.verifyUnchanged)
        }
        try verify(artifact) // Also catches synchronous reentry during barrier release.
        return artifact
    }

    /// On reopen the read-only server projection can now see our own accepted
    /// log. Name-level observation alone never clears a conflict: only c1's exact
    /// exercise ACK, after its full ABA/candidate/transport checks, may do so.
    private func acknowledgingExactHistory(_ capture: DayComposerFinalSourceCapture,
        server: DayComposerSourceServerFacts) throws -> DayComposerFinalSourceCapture {
        let local = capture.local
        guard local.itemFacts.contains(where: \.localConflictsWithServer) else { return capture }
        let provisional = DayComposerFinalSourceCapture(local: .init(identity: local.identity, source: local.source,
            canonicalPlan: local.canonicalPlan, itemFacts: local.itemFacts.map {
                .init(itemID: $0.itemID, local: $0.local, draft: $0.draft, localConflictsWithServer: false)
            }, comment: local.comment, guardValue: local.guardValue), finalInputs: capture.finalInputs)
        let initial = try history(identity: local.identity, source: local.source)
        let snapshot = try DayComposerFinalizationSnapshot.build(input(provisional, server: server, history: initial)).get()
        let resolved = try history(identity: local.identity, source: local.source,
            keys: snapshot.exerciseVersions.map { try $0.operationKey(identity: local.identity) })
        let facts = local.itemFacts.map { fact -> DayComposerRequiredItemFacts in
            guard fact.localConflictsWithServer,
                  let version = snapshot.exerciseVersions.first(where: { $0.itemID == fact.itemID }),
                  DayComposerFinalizationReconciliation.exercise(version, snapshot: snapshot, history: resolved) == .applicationConfirmed else {
                return fact
            }
            return .init(itemID: fact.itemID, local: fact.local, draft: fact.draft, localConflictsWithServer: false)
        }
        return .init(local: .init(identity: local.identity, source: local.source, canonicalPlan: local.canonicalPlan,
            itemFacts: facts, comment: local.comment, guardValue: local.guardValue), finalInputs: capture.finalInputs)
    }

    private func verify(_ artifact: DayComposerPreparedFinalization) throws {
        guard let execution, execution.revalidateExecutionContext() else { throw Failure.contextRejected }
        do {
            try artifact.verifyUnchanged()
            try execution.verifyFinalCapture(artifact.capture)
        }
        catch DayComposerStabilizationError.contextRejected { throw Failure.contextRejected }
        catch { throw Failure.staleSnapshot }
        guard try inputs.verify(artifact.capture.finalInputs), try inputs.verifyCaptureBinding(artifact.binding),
              try store.load(identity: artifact.reference.executionIdentity)?.sourceSnapshots.contains(where: {
                  $0.sourceVersion == artifact.reference.sourceVersion && $0.provenanceGuard == artifact.reference.provenanceGuard
              }) == true else { throw Failure.staleSnapshot }
    }

    private func reconcile(_ artifact: DayComposerPreparedFinalization,
                           server: DayComposerSourceServerFacts) throws -> DayComposerSourceFinishState {
        let adapter = artifact.adapter
        let facts = try history(identity: adapter.snapshot.identity, source: adapter.snapshot.source,
            keys: adapter.exercises.map(\.operationKey) + [adapter.finalKey])
        return DayComposerFinalizationReconciliation.source(input(artifact.capture, server: server, history: facts),
            finalPayload: adapter.finalVersion)
    }

    private func application<T>(_ outcome: NeutralSubmissionOutcome<T>) -> DayComposerApplicationState? {
        switch outcome {
        case .applicationConfirmed: return .confirmed
        case .applicationFailure: return .failure
        case .invalidResponse: return .invalidResponse
        default: return nil // f1 remains the sole durable transport truth.
        }
    }

    /// Reconcile-first, bounded progress. No blind resend, cleanup, polling or
    /// owner mutation. One source's pending transport never sets a global error.
    func advanceSource(_ artifact: DayComposerPreparedFinalization) async -> Result {
        let adapter = artifact.adapter
        let snapshot = adapter.snapshot
        let source = snapshot.source
        guard busy.insert(source).inserted else { return .init(reconciliation: nil, actions: [], error: .busy) }
        defer { phases[source] = .idle; busy.remove(source) }
        var state: DayComposerSourceFinishState?
        var actions: [Action] = []
        func result(_ error: Failure? = nil) -> Result { .init(reconciliation: state, actions: actions, error: error) }
        do {
            phases[source] = .reconciling
            try verify(artifact)
            var server: DayComposerSourceServerFacts
            do { server = try await readServer(snapshot.identity, source) }
            catch {
                try verify(artifact)
                try Task.checkCancellation()
                throw Failure.contextRejected // No fresh context facts, not a disk failure.
            }
            try verify(artifact)
            guard server.source == source, server.date == snapshot.identity.date else { throw Failure.contextRejected }
            state = try reconcile(artifact, server: server)
            try Task.checkCancellation()
            for request in adapter.exercises {
                guard let current = state else { throw Failure.contextRejected }
                guard let version = try snapshot.exerciseVersions.first(where: {
                    try $0.operationKey(identity: snapshot.identity) == request.operationKey
                }) else { throw Failure.contextRejected }
                if current.dependencies.items[version.itemID] == .applicationConfirmed { continue }
                guard current.isFinalizable,
                      current.dependencies.items[version.itemID] == .notSubmitted else { return result() }
                phases[source] = .submittingExercise
                try verify(artifact)
                try Task.checkCancellation()
                try store.recordExerciseIntent(identity: snapshot.identity, version: version)
                try store.markSubmissionMayHaveStarted(identity: snapshot.identity, operationKey: request.operationKey)
                guard try store.load(identity: snapshot.identity)?.exerciseIntents.contains(where: {
                    $0.exerciseVersion == version && $0.operationKey == request.operationKey
                        && $0.submissionPhase == .submissionMayHaveStarted
                }) == true else { throw Failure.durabilityFailure }
                try verify(artifact)
                try Task.checkCancellation()
                actions.append(.exercise(request.operationKey))
                let outcome = await dependencies.exercise(request)
                // Store OLD exact response before any stale/cancellation check.
                if let app = application(outcome) {
                    try store.recordExerciseApplication(identity: snapshot.identity, version: version, state: app)
                    guard try store.exerciseEvidence(identity: snapshot.identity, version: version) == app else { throw Failure.durabilityFailure }
                }
                try verify(artifact)
                state = try reconcile(artifact, server: server)
                try Task.checkCancellation()
                guard application(outcome) == .confirmed else { return result() }
            }
            guard let current = state else { throw Failure.contextRejected }
            if current.canSubmitFinal {
                phases[source] = .submittingFinal
                try verify(artifact)
                try Task.checkCancellation()
                try store.recordFinalIntent(identity: snapshot.identity, sourceVersion: snapshot.sourceVersion,
                    finalPayloadVersion: adapter.finalVersion, provenanceGuard: snapshot.provenanceGuard)
                try store.markSubmissionMayHaveStarted(identity: snapshot.identity, operationKey: adapter.finalKey)
                guard try store.load(identity: snapshot.identity)?.finalIntents.contains(where: {
                    $0.operationKey == adapter.finalKey && $0.finalPayloadVersion == adapter.finalVersion
                        && $0.sourceVersion == snapshot.sourceVersion && $0.provenanceGuard == snapshot.provenanceGuard
                        && $0.submissionPhase == .submissionMayHaveStarted
                }) == true else { throw Failure.durabilityFailure }
                let request = try adapter.finalRequest(dependencies: current.dependencies.state)
                try verify(artifact)
                try Task.checkCancellation()
                actions.append(.final(adapter.finalKey))
                let outcome = await dependencies.final(request)
                if let app = application(outcome) {
                    try store.recordFinalApplication(identity: snapshot.identity, sourceVersion: snapshot.sourceVersion,
                        finalPayloadVersion: adapter.finalVersion, state: app)
                    guard try store.finalEvidence(identity: snapshot.identity, sourceVersion: snapshot.sourceVersion,
                        finalPayloadVersion: adapter.finalVersion) == app else { throw Failure.durabilityFailure }
                }
                try verify(artifact)
                state = try reconcile(artifact, server: server)
                try Task.checkCancellation()
            }
            if state?.finalOperation.state == .applicationConfirmedCompletionUnknown
                || state?.finalOperation.state == .deliveredUnverified {
                phases[source] = .observingCompletion
                try verify(artifact)
                try Task.checkCancellation()
                actions.append(.completion)
                let observed = await dependencies.completion(source, snapshot.identity.date)
                let stored: DayComposerCompletionObservationRecord.Result
                switch observed {
                case .observed: stored = .observed
                case .unconfirmed: stored = .unconfirmed
                case .lookupFailure: stored = .lookupFailure
                case .unsupportedDate: stored = .unsupportedDate
                }
                let observation = try DayComposerCompletionObservationRecord(source: source, date: snapshot.identity.date,
                    result: stored, observedAt: Date(), sourceVersion: snapshot.sourceVersion)
                try store.recordCompletionObservation(identity: snapshot.identity, observation: observation)
                guard try store.load(identity: snapshot.identity)?.completionObservations.contains(observation) == true else { throw Failure.durabilityFailure }
                try verify(artifact)
                server = .init(source: source, date: server.date,
                    freshness: observed == .lookupFailure || observed == .unsupportedDate ? .unknown : .fresh,
                    observedNames: server.observedNames,
                    completion: observed == .observed ? .completedObserved : observed == .unconfirmed ? .notCompleted : .unknown)
                state = try reconcile(artifact, server: server)
                try Task.checkCancellation()
            }
            return result()
        } catch let error as Failure { return result(error) }
        catch is CancellationError { return result(.cancelled) }
        catch { return result(.durabilityFailure) }
    }
}
