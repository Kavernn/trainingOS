import Foundation

/// Evidence supplied by a future real barrier. No timer or owner inspection here.
/// A stable claim is bound to the exact inventory revision that was accepted.
enum DayComposerLocalStabilizationState: Equatable {
    case stableAccepted(DayComposerFinalizationGuard)
    case pendingLocalWrites, rejectedLocalWrite, unresolvedDraft, corruptDraft, unknown
}

enum DayComposerFactFreshness: Equatable { case fresh, stale, unknown }
enum DayComposerSourceCompletion: Equatable { case notCompleted, completedObserved, unknown }
enum DayComposerRawDraftFact: Equatable { case absent, present, corrupt }

/// Bytes are the already-built f2a request for a locally accepted, persisted log.
/// The adapter must establish persistence; this layer neither reads nor writes it.
enum DayComposerLocalResultFact: Equatable {
    case none
    case persisted(payload: Data, readOnly: Bool)
    case invalid

    var payload: Data? {
        if case .persisted(let data, _) = self { return data }
        return nil
    }
}

struct DayComposerRequiredItemFacts: Equatable {
    let itemID: DayComposerItemID
    let local: DayComposerLocalResultFact
    let draft: DayComposerRawDraftFact
    let localConflictsWithServer: Bool
}

struct DayComposerSourceServerFacts: Equatable {
    let source: DayComposerSource
    let date: String
    let freshness: DayComposerFactFreshness
    let observedNames: Set<String>
    let completion: DayComposerSourceCompletion
}

enum DayComposerReadinessReason: Equatable {
    case contextMismatch, provenanceMismatch, invalidFacts, zeroExecutableItems
    case stabilizationRequired, persistenceRejected, serverFactsNotFresh, completionUnknown
    case missing(DayComposerItemID), draft(DayComposerItemID), corruptDraft(DayComposerItemID)
    case localConflict(DayComposerItemID), invalidResult(DayComposerItemID), unsupported(DayComposerItemID)
    case completedWithUnacknowledgedWork
}

struct DayComposerSourceReadiness: Equatable {
    enum State: Equatable { case untouched, partial, ready, alreadyCompletedClean, reviewRequired, blockedContext }
    enum Satisfaction: Equatable { case local, serverObserved, incomplete, review }
    struct Item: Equatable {
        let id: DayComposerItemID
        let satisfaction: Satisfaction
    }
    let state: State
    let items: [Item]
    let reasons: [DayComposerReadinessReason]
}

enum DayComposerReadiness {
    static func supports(_ item: DayComposerItem) -> Bool {
        ["reps", "time", "carry", "plyo", "protocol", "mobility"].contains(item.tracking)
    }

    static func evaluate(_ input: DayComposerSourceFinalizationInput) -> DayComposerSourceReadiness {
        if let reason = input.contextRefusal {
            return .init(state: .blockedContext, items: [], reasons: [reason])
        }
        var reasons: [DayComposerReadinessReason] = []
        var review = false
        let stable: Bool
        switch input.stabilization {
        case .stableAccepted(let guardValue):
            stable = guardValue == input.provenanceGuard
            if !stable { reasons.append(.provenanceMismatch); review = true }
        case .rejectedLocalWrite:
            stable = false; reasons.append(.persistenceRejected); review = true
        case .unresolvedDraft, .corruptDraft:
            stable = false; reasons.append(.stabilizationRequired); review = true
        case .pendingLocalWrites, .unknown:
            stable = false; reasons.append(.stabilizationRequired)
        }
        let fresh = input.server.freshness == .fresh && input.contextFreshness == .fresh
        if !fresh { reasons.append(.serverFactsNotFresh) }
        if input.server.completion == .unknown { reasons.append(.completionUnknown) }
        if !input.planItems.contains(where: supports) {
            reasons.append(.zeroExecutableItems); review = true
        }
        let items: [DayComposerSourceReadiness.Item] = input.planItems.map { item in
            let fact = input.facts(for: item.id)
            let observed = fresh && input.server.observedNames.contains(item.storageKey)
            func result(_ satisfaction: DayComposerSourceReadiness.Satisfaction) -> DayComposerSourceReadiness.Item {
                .init(id: item.id, satisfaction: satisfaction)
            }
            if fact.draft == .corrupt {
                reasons.append(.corruptDraft(item.id)); review = true; return result(.review)
            }
            if fact.localConflictsWithServer || (fact.draft == .present && (fact.local != .none || observed)) {
                reasons.append(.localConflict(item.id)); review = true; return result(.review)
            }
            if fact.local == .invalid || !input.validPayload(for: item, fact: fact) {
                reasons.append(.invalidResult(item.id)); review = true; return result(.review)
            }
            if !supports(item) {
                if observed && fact.draft == .absent && fact.local == .none { return result(.serverObserved) }
                reasons.append(.unsupported(item.id)); review = true; return result(.review)
            }
            if fact.draft == .present {
                reasons.append(.draft(item.id)); return result(.incomplete)
            }
            if fact.local.payload != nil { return result(.local) }
            if observed { return result(.serverObserved) }
            reasons.append(.missing(item.id)); return result(.incomplete)
        }
        if input.server.completion == .completedObserved {
            // A historical snapshot alone is NOT an ACK. Require a confirmed final
            // intent and confirmed exact dependencies with no competing effects.
            if stable && fresh && !review && input.hasAcknowledgedLocalWork {
                return .init(state: .alreadyCompletedClean, items: items, reasons: [])
            }
            reasons.append(.completedWithUnacknowledgedWork)
            return .init(state: .reviewRequired, items: items, reasons: reasons)
        }
        if review { return .init(state: .reviewRequired, items: items, reasons: reasons) }
        if stable && fresh && input.server.completion == .notCompleted && items.allSatisfy({ $0.satisfaction != .incomplete }) {
            return .init(state: .ready, items: items, reasons: [])
        }
        let untouched = input.comment.isEmpty && input.itemFacts.allSatisfy {
            $0.local == .none && $0.draft == .absent && !$0.localConflictsWithServer
        } && input.server.observedNames.isEmpty && reasons.allSatisfy {
            if case .missing = $0 { return true }; return false
        }
        return .init(state: untouched ? .untouched : .partial, items: items, reasons: reasons)
    }
}
