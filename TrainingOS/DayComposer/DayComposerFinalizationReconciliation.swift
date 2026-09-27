import Foundation

/// A value projection, not a lookup. Missing dictionary entries are UNKNOWN,
/// never notFound. The future adapter must resolve every relevant operation key.
enum DayComposerTransportFact: Equatable {
    case notLookedUp, notFound, pending, delivered, discarded, uncertain

    init(_ status: OfflineMutationStatus) {
        switch status {
        case .notFound: self = .notFound
        case .pending: self = .pending
        case .delivered: self = .delivered
        case .discarded: self = .discarded
        case .uncertain: self = .uncertain
        }
    }
}

enum DayComposerDurabilityFact: Equatable {
    case trusted, unavailable, corruptCurrent, corruptCandidates, writeFailed
}

enum DayComposerGlobalFinalizationBlock: Equatable {
    case context, provenance, durability, candidateScan
}

struct DayComposerFinalizationHistory {
    let durability: DayComposerDurabilityFact
    let current: DayComposerFinalizationRecord?
    let candidates: [DayComposerFinalizationRecord]
    let transports: [OfflineOperationKey: DayComposerTransportFact]

    func transport(_ key: OfflineOperationKey) -> DayComposerTransportFact { transports[key] ?? .notLookedUp }

    func globalBlock(identity: DayComposerExecutionIdentity) -> DayComposerGlobalFinalizationBlock? {
        if durability == .corruptCandidates { return .candidateScan }
        guard durability == .trusted else { return .durability }
        if let current {
            guard current.executionIdentity == identity else { return .context }
            guard (try? current.validate()) != nil else { return .durability }
        }
        guard candidates.allSatisfy({ (try? $0.validate()) != nil }) else { return .candidateScan }
        // A scanner may include the current record. It must not supply two
        // contradictory copies of one execution, or silently omit a current copy.
        var seen: [DayComposerExecutionIdentity: DayComposerFinalizationRecord] = [:]
        for record in candidates {
            if record.executionIdentity == identity && record != current { return .candidateScan }
            if let prior = seen[record.executionIdentity], prior != record { return .candidateScan }
            seen[record.executionIdentity] = record
        }
        return nil
    }
}

enum DayComposerExerciseDependencyState: Equatable {
    case notSubmitted, applicationConfirmed, pending, deliveredUnverified, discarded, uncertain
    case applicationFailure, invalidResponse, staleOrConflicting, durabilityBlocked
}

struct DayComposerSourceDependencies: Equatable {
    let items: [DayComposerItemID: DayComposerExerciseDependencyState]
    var state: NeutralSourceDependencies {
        let values = Array(items.values)
        if values.contains(.durabilityBlocked) || values.contains(.staleOrConflicting)
            || values.contains(.applicationFailure) || values.contains(.invalidResponse) || values.contains(.discarded) { return .failed }
        if values.contains(.uncertain) { return .uncertain }
        if values.contains(.deliveredUnverified) || values.contains(.notSubmitted) { return .unverified }
        if values.contains(.pending) { return .waiting }
        return .satisfied
    }
}

enum DayComposerOldCandidateImpact: Equatable {
    case irrelevantHistorical, blocksCurrent, requiresReview, historicalResolvedFact
}

struct DayComposerFinalOperationState: Equatable {
    enum State: Equatable {
        case notPrepared, readyToSubmit, pending, deliveredUnverified
        case applicationConfirmedCompletionUnknown, completedObserved
        case discarded, uncertain, applicationFailure, invalidResponse
        case stale, durabilityBlocked, reviewRequired
    }
    let state: State
    let application: DayComposerApplicationState
    let completion: DayComposerSourceCompletion
    let hasIntent: Bool
}

enum DayComposerRetryDecision: Equatable {
    case prepareAndSubmit, resumeIntent, wait, refreshOnly, reviewRequired, noActionResolved, blocked
}

struct DayComposerSourceFinishState: Equatable {
    let identity: DayComposerExecutionIdentity
    let source: DayComposerSource
    let readiness: DayComposerSourceReadiness
    let freshness: DayComposerFactFreshness
    let stabilization: DayComposerLocalStabilizationState
    let dependencies: DayComposerSourceDependencies
    let finalOperation: DayComposerFinalOperationState
    let finalInputsAvailable: Bool
    let completion: DayComposerSourceCompletion
    let candidateImpacts: [DayComposerOldCandidateImpact]
    let globalBlock: DayComposerGlobalFinalizationBlock?
    let retry: DayComposerRetryDecision

    var isResolved: Bool { globalBlock == nil && retry == .noActionResolved }
    /// Eligible for a future pipeline (which may first need exercise POSTs).
    /// NOT permission to call the final endpoint directly.
    var isFinalizable: Bool { globalBlock == nil && (retry == .prepareAndSubmit || retry == .resumeIntent) }
    var canSubmitFinal: Bool {
        isFinalizable && finalInputsAvailable && dependencies.state == .satisfied && finalOperation.state == .readyToSubmit
    }
    var hasPending: Bool { finalOperation.state == .pending || dependencies.items.values.contains(.pending) }
    var requiresReview: Bool {
        retry == .reviewRequired || readiness.state == .reviewRequired
            || finalOperation.state == .deliveredUnverified || finalOperation.state == .uncertain
            || dependencies.items.values.contains(.deliveredUnverified) || dependencies.items.values.contains(.uncertain)
    }
}

struct DayComposerCompositeFinishState: Equatable {
    let morning: DayComposerSourceFinishState
    let evening: DayComposerSourceFinishState
    var globalBlock: DayComposerGlobalFinalizationBlock? {
        guard morning.identity == evening.identity, morning.source == .morning, evening.source == .evening else { return .context }
        return morning.globalBlock ?? evening.globalBlock
    }
    var hasPending: Bool { morning.hasPending || evening.hasPending }
    var hasReviewRequired: Bool { globalBlock != nil || morning.requiresReview || evening.requiresReview }
    var hasFinalizableSource: Bool { globalBlock == nil && (morning.isFinalizable || evening.isFinalizable) }
    var allRequiredSourcesResolved: Bool { globalBlock == nil && morning.isResolved && evening.isResolved }
    /// A domain suggestion only, never a dismiss/cleanup side effect.
    var canDismiss: Bool { allRequiredSourcesResolved }
}

enum DayComposerFinalizationReconciliation {
    private static func mayHaveEffects(_ phase: DayComposerSubmissionPhase, _ app: DayComposerApplicationState,
                                       _ transport: DayComposerTransportFact) -> Bool {
        phase == .submissionMayHaveStarted || app != .unknown || transport != .notFound
    }

    private static func operation(phase: DayComposerSubmissionPhase?, application: DayComposerApplicationState,
                                  transport: DayComposerTransportFact) -> DayComposerExerciseDependencyState {
        guard let phase else { return transport == .notFound ? .notSubmitted : .uncertain }
        if phase == .intentRecorded && (application != .unknown || transport != .notFound) { return .uncertain }
        // Contradictory transport evidence cannot be overridden by an old ACK.
        if transport == .uncertain || transport == .notLookedUp { return .uncertain }
        if application != .unknown && (transport == .pending || transport == .discarded) { return .staleOrConflicting }
        switch application {
        case .confirmed: return .applicationConfirmed
        case .failure: return .applicationFailure
        case .invalidResponse: return .invalidResponse
        case .unknown: break
        }
        switch transport {
        case .pending: return .pending
        case .delivered: return .deliveredUnverified
        case .discarded: return .discarded
        case .notFound: return phase == .intentRecorded ? .notSubmitted : .uncertain
        case .uncertain, .notLookedUp: return .uncertain
        }
    }

    static func candidate(_ record: DayComposerFinalizationRecord, identity: DayComposerExecutionIdentity,
                          source: DayComposerSource, history: DayComposerFinalizationHistory) -> DayComposerOldCandidateImpact {
        guard record.executionIdentity != identity, record.executionIdentity.date == identity.date,
              record.contains(source: source) else { return .irrelevantHistorical }
        let operations = record.exerciseIntents.filter { $0.exerciseVersion.source == source }.map {
            ($0.submissionPhase, $0.applicationState, history.transport($0.operationKey))
        } + record.finalIntents.filter { $0.sourceVersion.source == source }.map {
            ($0.submissionPhase, $0.applicationState, history.transport($0.operationKey))
        }
        var confirmed = false
        for (phase, app, transport) in operations {
            guard mayHaveEffects(phase, app, transport) else { continue }
            let state = operation(phase: phase, application: app, transport: transport)
            if state == .applicationConfirmed { confirmed = true; continue }
            if state == .pending || state == .uncertain { return .blocksCurrent }
            return .requiresReview
        }
        // A completion fact is historical too, never a current application ACK.
        if record.completionObservations.contains(where: { $0.source == source && $0.result == .observed }) { confirmed = true }
        return confirmed ? .historicalResolvedFact : .irrelevantHistorical
    }

    static func exercise(_ version: DayComposerExerciseVersion, snapshot: DayComposerFinalizationSnapshot,
                         history: DayComposerFinalizationHistory) -> DayComposerExerciseDependencyState {
        guard history.globalBlock(identity: snapshot.identity) == nil else { return .durabilityBlocked }
        guard snapshot.exerciseVersions.contains(version), version.source == snapshot.source,
              let key = try? version.operationKey(identity: snapshot.identity) else { return .staleOrConflicting }
        if history.candidates.contains(where: {
            candidate($0, identity: snapshot.identity, source: snapshot.source, history: history) != .irrelevantHistorical
        }) { return .staleOrConflicting }
        let intents = history.current?.exerciseIntents.filter { $0.exerciseVersion.itemID == version.itemID } ?? []
        // Conservative ABA rule: never guess which different submitted version
        // is latest from timestamps or insertion order. Unsent intents are safe.
        if intents.contains(where: {
            $0.exerciseVersion != version && mayHaveEffects($0.submissionPhase, $0.applicationState, history.transport($0.operationKey))
        }) { return .staleOrConflicting }
        let exact = intents.first { $0.exerciseVersion == version }
        return operation(phase: exact?.submissionPhase, application: exact?.applicationState ?? .unknown,
                         transport: history.transport(key))
    }

    static func final(snapshot: DayComposerFinalizationSnapshot, history: DayComposerFinalizationHistory,
                      payload: DayComposerFinalPayloadVersion?, completion: DayComposerSourceCompletion) -> DayComposerFinalOperationState {
        func result(_ state: DayComposerFinalOperationState.State, _ app: DayComposerApplicationState = .unknown,
                    _ hasIntent: Bool = false) -> DayComposerFinalOperationState {
            .init(state: state, application: app, completion: completion, hasIntent: hasIntent)
        }
        guard history.globalBlock(identity: snapshot.identity) == nil else { return result(.durabilityBlocked) }
        if history.candidates.contains(where: {
            candidate($0, identity: snapshot.identity, source: snapshot.source, history: history) != .irrelevantHistorical
        }) { return result(.reviewRequired) }
        let intents = history.current?.finalIntents.filter { $0.sourceVersion.source == snapshot.source } ?? []
        // Reopen can inspect a unique persisted final version without rebuilding
        // its private payload. This is observation, not permission to resubmit it.
        let matching = intents.filter { $0.sourceVersion == snapshot.sourceVersion && $0.provenanceGuard == snapshot.provenanceGuard }
        guard let payload = payload ?? (matching.count == 1 ? matching.first?.finalPayloadVersion : nil) else {
            return result(intents.isEmpty ? .notPrepared : .reviewRequired)
        }
        guard let key = try? payload.operationKey(identity: snapshot.identity, sourceVersion: snapshot.sourceVersion) else { return result(.reviewRequired) }
        let exact = intents.first { $0.operationKey == key }
        if intents.contains(where: {
            $0.operationKey != key && mayHaveEffects($0.submissionPhase, $0.applicationState, history.transport($0.operationKey))
        }) { return result(.stale) }
        if let exact, exact.provenanceGuard != snapshot.provenanceGuard { return result(.reviewRequired, exact.applicationState, true) }
        let app = exact?.applicationState ?? .unknown
        switch operation(phase: exact?.submissionPhase, application: app, transport: history.transport(key)) {
        case .notSubmitted: return result(.readyToSubmit, app, exact != nil)
        case .applicationConfirmed:
            return result(completion == .completedObserved ? .completedObserved : .applicationConfirmedCompletionUnknown, app, true)
        case .pending: return result(.pending, app, true)
        case .deliveredUnverified: return result(.deliveredUnverified, app, true)
        case .discarded: return result(.discarded, app, true)
        case .uncertain: return result(.uncertain, app, exact != nil)
        case .applicationFailure: return result(.applicationFailure, app, true)
        case .invalidResponse: return result(.invalidResponse, app, true)
        case .staleOrConflicting: return result(.reviewRequired, app, exact != nil)
        case .durabilityBlocked: return result(.durabilityBlocked)
        }
    }

    /// No invocation, persistence, timestamp, intent creation or retry loop.
    /// finalPayload is optional: c1 never invents RPE/duration to construct it.
    static func source(_ input: DayComposerSourceFinalizationInput,
                       finalPayload: DayComposerFinalPayloadVersion? = nil) -> DayComposerSourceFinishState {
        let readiness = DayComposerReadiness.evaluate(input)
        var global = input.history.globalBlock(identity: input.identity)
        if let reason = input.contextRefusal { global = reason == .provenanceMismatch ? .provenance : .context }
        let impacts = input.history.candidates.map { candidate($0, identity: input.identity, source: input.source, history: input.history) }
        var dependencies: [DayComposerItemID: DayComposerExerciseDependencyState] = [:]
        var finalState = DayComposerFinalOperationState(state: .notPrepared, application: .unknown,
            completion: input.server.completion, hasIntent: false)
        if case .success(let snapshot) = DayComposerFinalizationSnapshot.build(input) {
            for version in snapshot.exerciseVersions {
                dependencies[version.itemID] = exercise(version, snapshot: snapshot, history: input.history)
            }
            finalState = final(snapshot: snapshot, history: input.history, payload: finalPayload, completion: input.server.completion)
            // A positive server observation must not hide a removed local version
            // whose operation can still affect this source. Inspect the WHOLE
            // source history, not just dependencies present in today's snapshot.
            if input.history.current?.exerciseIntents.contains(where: {
                $0.exerciseVersion.source == input.source && !snapshot.exerciseVersions.contains($0.exerciseVersion)
                    && mayHaveEffects($0.submissionPhase, $0.applicationState, input.history.transport($0.operationKey))
            }) == true {
                finalState = .init(state: .stale, application: .unknown, completion: input.server.completion, hasIntent: false)
            }
        } else if readiness.state == .ready || readiness.state == .alreadyCompletedClean {
            // Never offer pipeline eligibility after a failed canonical capture.
            finalState = .init(state: .reviewRequired, application: .unknown,
                completion: input.server.completion, hasIntent: false)
        }
        let sourceDependencies = DayComposerSourceDependencies(items: dependencies)
        let untracked = input.history.current.map { record in
            record.exerciseIntents.contains {
                $0.exerciseVersion.source == input.source && $0.submissionPhase == .submissionMayHaveStarted
                    && $0.applicationState == .unknown && input.history.transport($0.operationKey) == .notFound
            } || record.finalIntents.contains {
                $0.sourceVersion.source == input.source && $0.submissionPhase == .submissionMayHaveStarted
                    && $0.applicationState == .unknown && input.history.transport($0.operationKey) == .notFound
            }
        } ?? false
        let retry = decision(readiness: readiness, fresh: input.server.freshness == .fresh && input.contextFreshness == .fresh,
            dependencies: sourceDependencies, final: finalState, candidates: impacts, global: global, untrackedAttempt: untracked)
        return .init(identity: input.identity, source: input.source, readiness: readiness,
            freshness: input.server.freshness == .fresh ? input.contextFreshness : input.server.freshness,
            stabilization: input.stabilization, dependencies: sourceDependencies, finalOperation: finalState,
            finalInputsAvailable: finalPayload != nil,
            completion: input.server.completion, candidateImpacts: impacts, globalBlock: global, retry: retry)
    }

    private static func decision(readiness: DayComposerSourceReadiness, fresh: Bool,
                                 dependencies: DayComposerSourceDependencies, final: DayComposerFinalOperationState,
                                 candidates: [DayComposerOldCandidateImpact], global: DayComposerGlobalFinalizationBlock?,
                                 untrackedAttempt: Bool) -> DayComposerRetryDecision {
        if global != nil { return .blocked }
        if untrackedAttempt { return .reviewRequired }
        if candidates.contains(.blocksCurrent) || candidates.contains(.requiresReview) { return .reviewRequired }
        if readiness.state == .reviewRequired { return .reviewRequired }
        if readiness.state == .blockedContext { return .blocked }
        if !fresh { return .refreshOnly }
        let states = Array(dependencies.items.values)
        if states.contains(.staleOrConflicting) || states.contains(.applicationFailure)
            || states.contains(.invalidResponse) || states.contains(.discarded) { return .reviewRequired }
        if states.contains(.durabilityBlocked) { return .blocked }
        if states.contains(.uncertain) || states.contains(.deliveredUnverified) { return .refreshOnly }
        if states.contains(.pending) { return .wait }
        // Even completed-clean cannot conceal an unresolved final operation.
        switch final.state {
        case .pending: return .wait
        case .deliveredUnverified, .uncertain, .applicationConfirmedCompletionUnknown: return .refreshOnly
        case .discarded, .applicationFailure, .invalidResponse, .stale, .reviewRequired: return .reviewRequired
        case .durabilityBlocked: return .blocked
        default: break
        }
        if readiness.state == .alreadyCompletedClean {
            return states.allSatisfy { $0 == .applicationConfirmed } ? .noActionResolved : .reviewRequired
        }
        if candidates.contains(.historicalResolvedFact) { return .reviewRequired }
        guard readiness.state == .ready else { return .blocked }
        switch final.state {
        case .completedObserved:
            return dependencies.state == .satisfied ? .noActionResolved : .reviewRequired
        case .applicationConfirmedCompletionUnknown: return .refreshOnly
        case .readyToSubmit: return final.hasIntent ? .resumeIntent : .prepareAndSubmit
        case .notPrepared: return .prepareAndSubmit // Pipeline eligibility, NOT a final POST permit.
        default: return .reviewRequired
        }
    }
}
