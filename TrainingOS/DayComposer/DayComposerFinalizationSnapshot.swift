import Foundation

/// Immutable value input. Server freshness and accepted persistence must be
/// established by the future adapter, never inferred from wall-clock timestamps.
struct DayComposerSourceFinalizationInput {
    let identity: DayComposerExecutionIdentity
    let source: DayComposerSource
    let canonicalPlan: DayComposerSnapshot
    let contextFreshness: DayComposerFactFreshness
    let provenanceGuard: DayComposerFinalizationGuard
    let provenanceCompatible: Bool
    let stabilization: DayComposerLocalStabilizationState
    let itemFacts: [DayComposerRequiredItemFacts]
    let comment: String
    let server: DayComposerSourceServerFacts
    /// Caller-supplied, validated historical facts. Never loaded by this type.
    let history: DayComposerFinalizationHistory

    var sessionName: String { identity.session(for: source) }
    var planItems: [DayComposerItem] {
        let plan = source == .morning ? canonicalPlan.morning : canonicalPlan.evening
        return plan.units.flatMap(\.items).sorted {
            $0.sourceOrder != $1.sourceOrder ? $0.sourceOrder < $1.sourceOrder
                : DayComposerFinalizationCoding.precedes($0.id, $1.id)
        }
    }

    var contextRefusal: DayComposerReadinessReason? {
        guard let context = try? DayComposerExecutionContext(snapshot: canonicalPlan),
              let expected = try? DayComposerExecutionIdentity(executionID: identity.executionID, context: context),
              expected == identity, server.source == source, server.date == identity.date else { return .contextMismatch }
        guard provenanceCompatible,
              (try? provenanceGuard.validate(identity: identity, source: source)) != nil else { return .provenanceMismatch }
        let ids = planItems.map(\.id)
        guard Set(ids).count == ids.count, ids.allSatisfy({ $0.source == source }),
              Set(itemFacts.map(\.itemID)).count == itemFacts.count,
              itemFacts.allSatisfy({ ids.contains($0.itemID) }) else { return .invalidFacts }
        return nil
    }

    func facts(for id: DayComposerItemID) -> DayComposerRequiredItemFacts {
        itemFacts.first { $0.itemID == id } ?? .init(itemID: id, local: .none, draft: .absent, localConflictsWithServer: false)
    }

    /// Check routing without re-encoding the exact bytes used by f2a. Business
    /// validation/persistence acceptance is an explicit caller prerequisite.
    func validPayload(for item: DayComposerItem, fact: DayComposerRequiredItemFacts) -> Bool {
        guard let bytes = fact.local.payload else { return fact.local == .none }
        guard let json = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              json["exercise"] as? String == item.name,
              json["session_date"] as? String == identity.date,
              (json["is_second"] as? Bool ?? false) == (source == .evening),
              (json["is_bonus"] as? Bool ?? false) == false,
              json["weight"] is NSNumber, json["reps"] is String else { return false }
        return true
    }

    var hasAcknowledgedLocalWork: Bool {
        guard history.globalBlock(identity: identity) == nil,
              itemFacts.allSatisfy({ $0.draft == .absent && !$0.localConflictsWithServer && $0.local != .invalid }) else { return false }
        let hasLocal = !comment.isEmpty || itemFacts.contains { $0.local != .none }
            || history.current?.contains(source: source) == true
        guard hasLocal else { return true }
        guard case .success(let snapshot) = DayComposerFinalizationSnapshot.build(self),
              let record = history.current else { return false }
        return record.finalIntents.contains { intent in
            guard intent.sourceVersion == snapshot.sourceVersion,
                  intent.provenanceGuard == provenanceGuard, intent.applicationState == .confirmed else { return false }
            let dependencies = snapshot.exerciseVersions.map {
                DayComposerFinalizationReconciliation.exercise($0, snapshot: snapshot, history: history)
            }
            guard dependencies.allSatisfy({ $0 == .applicationConfirmed }) else { return false }
            return DayComposerFinalizationReconciliation.final(snapshot: snapshot, history: history,
                payload: intent.finalPayloadVersion, completion: server.completion).state == .completedObserved
        }
    }
}

enum DayComposerSnapshotRefusal: Error, Equatable {
    case context(DayComposerReadinessReason), stabilization, draft(DayComposerItemID)
    case invalidPayload(DayComposerItemID), invalidVersion
}

struct DayComposerFinalizationSnapshot: Equatable {
    let identity: DayComposerExecutionIdentity
    let source: DayComposerSource
    let provenanceGuard: DayComposerFinalizationGuard
    let sourceVersion: DayComposerSourceVersion
    /// Exact payloads, immutable and memory-only. f2b still persists only digests.
    let payloads: [DayComposerItemID: Data]
    var exerciseVersions: [DayComposerExerciseVersion] { sourceVersion.exerciseVersions }
    var dependencies: [DayComposerExerciseVersion] { exerciseVersions }

    private init(identity: DayComposerExecutionIdentity, source: DayComposerSource,
                 provenanceGuard: DayComposerFinalizationGuard, sourceVersion: DayComposerSourceVersion,
                 payloads: [DayComposerItemID: Data]) {
        self.identity = identity
        self.source = source
        self.provenanceGuard = provenanceGuard
        self.sourceVersion = sourceVersion
        self.payloads = payloads
    }

    static func build(_ input: DayComposerSourceFinalizationInput) -> Result<Self, DayComposerSnapshotRefusal> {
        if let refusal = input.contextRefusal { return .failure(.context(refusal)) }
        guard case .stableAccepted(let accepted) = input.stabilization,
              accepted == input.provenanceGuard else { return .failure(.stabilization) }
        var payloads: [DayComposerItemID: Data] = [:]
        var versions: [DayComposerExerciseVersion] = []
        do {
            for item in input.planItems {
                let fact = input.facts(for: item.id)
                guard fact.draft == .absent, !fact.localConflictsWithServer else { return .failure(.draft(item.id)) }
                guard input.validPayload(for: item, fact: fact) else { return .failure(.invalidPayload(item.id)) }
                if let bytes = fact.local.payload {
                    payloads[item.id] = bytes
                    versions.append(try .init(itemID: item.id, date: input.identity.date, payloadData: bytes))
                }
            }
            let version = try DayComposerSourceVersion(source: input.source, sessionName: input.sessionName,
                items: input.planItems, exerciseVersions: versions, comment: input.comment)
            try version.validate(identity: input.identity)
            return .success(.init(identity: input.identity, source: input.source,
                provenanceGuard: input.provenanceGuard, sourceVersion: version, payloads: payloads))
        } catch { return .failure(.invalidVersion) }
    }

    /// Same relation semantics as f2b, without inventing a capture timestamp.
    func relation(to current: DayComposerSourceFinalizationInput) -> DayComposerSourceSnapshotRecord.Relation {
        guard identity == current.identity, source == current.source, current.contextRefusal == nil else { return .contextMismatch }
        guard case .success(let other) = Self.build(current) else { return .unknown }
        guard sourceVersion == other.sourceVersion else { return .stale }
        return provenanceGuard == other.provenanceGuard ? .current : .revalidationRequired
    }
}
