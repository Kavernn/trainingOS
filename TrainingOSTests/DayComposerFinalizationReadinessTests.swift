import Foundation
import XCTest
#if canImport(TrainingOS)
@testable import TrainingOS
#endif

/// In-memory facts only. No stores, clock, queue, owners or transport instances.
enum FinalizationFactsFixture {
    static let date = "2026-09-27"
    static let execution = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static let instant = Date(timeIntervalSince1970: 1_790_000_000)

    static func plan(tracking: String = "reps", onlyUnsupported: Bool = false) throws -> DayComposerSnapshot {
        func source(_ source: DayComposerSource) throws -> DayComposerPlan {
            try .init(source: source, session: source == .morning ? "AM" : "PM",
                schemes: onlyUnsupported ? ["A": "3x8"] : ["A": "3x8", "B": "3x8"], order: ["A", "B"],
                tracking: ["A": tracking, "B": "reps"])
        }
        return try .init(date: date, activeProgramID: "program-A", morning: source(.morning), evening: source(.evening),
                         morningCompleted: false, eveningCompleted: false)
    }

    static func identity(_ plan: DayComposerSnapshot, execution: UUID = execution) throws -> DayComposerExecutionIdentity {
        try .init(executionID: execution, context: DayComposerExecutionContext(snapshot: plan))
    }

    static func guardValue(_ source: DayComposerSource = .morning, revision: Int = 0) throws -> DayComposerFinalizationGuard {
        try .init(executionID: execution, source: source, revision: revision,
                  integrity: DayComposerFinalizationCoding.hash(Data("inventory-\(source)-\(revision)".utf8)))
    }

    static func bytes(_ name: String, source: DayComposerSource, reps: String = "8") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["exercise": name, "session_date": date,
            "weight": 50, "reps": reps, "is_second": source == .evening, "is_bonus": false], options: [.sortedKeys])
    }

    static func facts(_ plan: DayComposerSnapshot, source: DayComposerSource, reps: String = "8") throws -> [DayComposerRequiredItemFacts] {
        try (source == .morning ? plan.morning : plan.evening).units.flatMap(\.items).map {
            .init(itemID: $0.id, local: .persisted(payload: try bytes($0.name, source: source, reps: reps), readOnly: false),
                  draft: .absent, localConflictsWithServer: false)
        }
    }

    static func input(source: DayComposerSource = .morning, plan: DayComposerSnapshot? = nil,
                      facts: [DayComposerRequiredItemFacts]? = nil, comment: String = "",
                      completion: DayComposerSourceCompletion = .notCompleted,
                      observed: Set<String> = [], freshness: DayComposerFactFreshness = .fresh,
                      contextFreshness: DayComposerFactFreshness = .fresh,
                      stabilization: DayComposerLocalStabilizationState? = nil,
                      revision: Int = 0, provenance: Bool = true,
                      history: DayComposerFinalizationHistory? = nil) throws -> DayComposerSourceFinalizationInput {
        let plan = try plan ?? self.plan()
        let id = try identity(plan)
        let guardValue = try guardValue(source, revision: revision)
        let itemFacts = try facts ?? self.facts(plan, source: source)
        // Explicit notFound lookups for the operation keys this fixture supplies.
        var transports: [OfflineOperationKey: DayComposerTransportFact] = [:]
        for fact in itemFacts {
            if let bytes = fact.local.payload {
                let version = try DayComposerExerciseVersion(itemID: fact.itemID, date: date, payloadData: bytes)
                transports[try version.operationKey(identity: id)] = .notFound
            }
        }
        return .init(identity: id, source: source, canonicalPlan: plan, contextFreshness: contextFreshness,
            provenanceGuard: guardValue, provenanceCompatible: provenance,
            stabilization: stabilization ?? .stableAccepted(guardValue), itemFacts: itemFacts, comment: comment,
            server: .init(source: source, date: date, freshness: freshness, observedNames: observed, completion: completion),
            history: history ?? .init(durability: .trusted, current: nil, candidates: [], transports: transports))
    }

    static func replacing(_ fact: DayComposerRequiredItemFacts, local: DayComposerLocalResultFact? = nil,
                          draft: DayComposerRawDraftFact? = nil, conflict: Bool = false) -> DayComposerRequiredItemFacts {
        .init(itemID: fact.itemID, local: local ?? fact.local, draft: draft ?? fact.draft, localConflictsWithServer: conflict)
    }

    static func snapshot(_ input: DayComposerSourceFinalizationInput) throws -> DayComposerFinalizationSnapshot {
        try DayComposerFinalizationSnapshot.build(input).get()
    }

    static func finalPayload(_ text: String = "final-7-nil") throws -> DayComposerFinalPayloadVersion {
        try .init(payloadData: Data(text.utf8))
    }

    static func record(_ snapshot: DayComposerFinalizationSnapshot,
                       application: DayComposerApplicationState = .confirmed,
                       phase: DayComposerSubmissionPhase = .submissionMayHaveStarted,
                       final: Bool = false) throws -> DayComposerFinalizationRecord {
        var record = try DayComposerFinalizationRecord(identity: snapshot.identity, now: instant)
        record.sourceSnapshots = [try .init(identity: snapshot.identity, sourceVersion: snapshot.sourceVersion,
            provenanceGuard: snapshot.provenanceGuard, createdAt: instant)]
        record.exerciseIntents = try snapshot.exerciseVersions.map {
            var intent = try DayComposerExerciseIntentRecord(identity: snapshot.identity, version: $0, now: instant)
            intent.submissionPhase = phase
            intent.applicationEvidence = application == .unknown ? nil : application
            return intent
        }
        if final {
            var intent = try DayComposerFinalIntentRecord(identity: snapshot.identity, sourceVersion: snapshot.sourceVersion,
                finalPayloadVersion: finalPayload(), provenanceGuard: snapshot.provenanceGuard, now: instant)
            intent.submissionPhase = phase
            intent.applicationState = application
            record.finalIntents = [intent]
        }
        try record.validate()
        return record
    }

    static func history(_ record: DayComposerFinalizationRecord?, transport: DayComposerTransportFact = .delivered,
                        candidates: [DayComposerFinalizationRecord] = [], durability: DayComposerDurabilityFact = .trusted,
                        extra: [OfflineOperationKey: DayComposerTransportFact] = [:]) -> DayComposerFinalizationHistory {
        var transports = extra
        for value in ([record].compactMap { $0 } + candidates) {
            for intent in value.exerciseIntents { transports[intent.operationKey] = transport }
            for intent in value.finalIntents { transports[intent.operationKey] = transport }
        }
        return .init(durability: durability, current: record, candidates: candidates, transports: transports)
    }
}

final class DayComposerFinalizationReadinessTests: XCTestCase {
    private typealias F = FinalizationFactsFixture

    func testAllLocalReadyAndReadOnlyResultAlsoSatisfied() throws {
        let input = try F.input()
        XCTAssertEqual(DayComposerReadiness.evaluate(input).state, .ready)
        var facts = input.itemFacts
        facts[0] = F.replacing(facts[0], local: .persisted(payload: facts[0].local.payload!, readOnly: true))
        XCTAssertEqual(DayComposerReadiness.evaluate(try F.input(facts: facts)).state, .ready)
    }

    func testMissingUntouchedDraftAndConflicts() throws {
        let facts = try F.input().itemFacts
        let cases: [(DayComposerLocalResultFact, DayComposerRawDraftFact, Bool, DayComposerSourceReadiness.State)] = [
            (.none, .absent, false, .partial), (.none, .present, false, .partial),
            (.none, .corrupt, false, .reviewRequired), (facts[0].local, .present, false, .reviewRequired),
            (facts[0].local, .absent, true, .reviewRequired), (.invalid, .absent, false, .reviewRequired)]
        for (local, draft, conflict, expected) in cases {
            XCTAssertEqual(DayComposerReadiness.evaluate(try F.input(facts: [
                F.replacing(facts[0], local: local, draft: draft, conflict: conflict), facts[1]])).state, expected)
        }
        XCTAssertEqual(DayComposerReadiness.evaluate(try F.input(facts: [])).state, .untouched)
    }

    func testObservedNeedsFreshnessAndNeverOverridesConflict() throws {
        XCTAssertEqual(DayComposerReadiness.evaluate(try F.input(facts: [], observed: ["A", "B"])).state, .ready)
        for fresh in [DayComposerFactFreshness.stale, .unknown] {
            XCTAssertNotEqual(DayComposerReadiness.evaluate(try F.input(facts: [], observed: ["A", "B"], freshness: fresh)).state, .ready)
        }
        let a = try F.input().itemFacts[0]
        XCTAssertEqual(DayComposerReadiness.evaluate(try F.input(facts: [F.replacing(a, local: DayComposerLocalResultFact.none, draft: .present)],
            observed: ["A", "B"])).state, .reviewRequired)
    }

    func testUnsupportedObservedAndZeroExecutablePolicy() throws {
        let plan = try F.plan(tracking: "unsupported")
        let b = try F.facts(plan, source: .morning)[1]
        XCTAssertEqual(DayComposerReadiness.evaluate(try F.input(plan: plan, facts: [b])).state, .reviewRequired)
        XCTAssertEqual(DayComposerReadiness.evaluate(try F.input(plan: plan, facts: [b], observed: ["A"])).state, .ready)
        let zero = try F.input(plan: F.plan(tracking: "unsupported", onlyUnsupported: true), facts: [], observed: ["A"])
        XCTAssertEqual(DayComposerReadiness.evaluate(zero).state, .reviewRequired)
        XCTAssertTrue(DayComposerReadiness.evaluate(zero).reasons.contains(.zeroExecutableItems))
    }

    func testInvalidContextAndForeignOrDuplicateFactsBlocked() throws {
        XCTAssertEqual(DayComposerReadiness.evaluate(try F.input(provenance: false)).state, .blockedContext)
        let facts = try F.input().itemFacts
        XCTAssertEqual(DayComposerReadiness.evaluate(try F.input(facts: facts + [facts[0]])).state, .blockedContext)
        XCTAssertEqual(DayComposerReadiness.evaluate(try F.input(facts: F.input(source: .evening).itemFacts)).state, .blockedContext)
    }

    func testCompletedCleanAndDirty() throws {
        XCTAssertEqual(DayComposerReadiness.evaluate(try F.input(facts: [], completion: .completedObserved)).state, .alreadyCompletedClean)
        XCTAssertEqual(DayComposerReadiness.evaluate(try F.input(facts: [], comment: "new", completion: .completedObserved)).state, .reviewRequired)
        XCTAssertEqual(DayComposerReadiness.evaluate(try F.input(completion: .completedObserved)).state, .reviewRequired)
        let a = try F.input().itemFacts[0]
        XCTAssertEqual(DayComposerReadiness.evaluate(try F.input(facts: [F.replacing(a, local: DayComposerLocalResultFact.none, draft: .present)],
            completion: .completedObserved)).state, .reviewRequired)
        XCTAssertEqual(DayComposerReadiness.evaluate(try F.input(facts: [], completion: .completedObserved,
            stabilization: .unknown)).state, .reviewRequired)
    }

    func testCompletedPersistedResultsRequireExactConfirmedFinalAndGuard() throws {
        let snap = try F.snapshot(F.input(comment: "accepted"))
        let history = try F.history(F.record(snap, final: true))
        XCTAssertEqual(DayComposerReadiness.evaluate(try F.input(comment: "accepted", completion: .completedObserved,
            history: history)).state, .alreadyCompletedClean)
        for comment in ["changed", ""] {
            XCTAssertEqual(DayComposerReadiness.evaluate(try F.input(comment: comment, completion: .completedObserved,
                history: history)).state, .reviewRequired)
        }
        XCTAssertEqual(DayComposerReadiness.evaluate(try F.input(comment: "accepted", completion: .completedObserved,
            revision: 1, history: history)).state, .reviewRequired)
        // Clearing every retained value must not resurrect a clean classification.
        XCTAssertEqual(DayComposerReadiness.evaluate(try F.input(facts: [], completion: .completedObserved,
            history: history)).state, .reviewRequired)
    }

    func testAllUnstableStatesRefuseSnapshotAndReady() throws {
        let states: [DayComposerLocalStabilizationState] = [.pendingLocalWrites, .rejectedLocalWrite,
            .unresolvedDraft, .corruptDraft, .unknown, .stableAccepted(try F.guardValue(revision: 4))]
        for state in states {
            let input = try F.input(stabilization: state)
            XCTAssertThrowsError(try F.snapshot(input))
            XCTAssertNotEqual(DayComposerReadiness.evaluate(input).state, .ready)
        }
        XCTAssertNoThrow(try F.snapshot(F.input()))
    }

    func testDraftAndInvalidPayloadRefuseSnapshot() throws {
        let facts = try F.input().itemFacts
        for draft in [DayComposerRawDraftFact.present, .corrupt] {
            XCTAssertThrowsError(try F.snapshot(F.input(facts: [F.replacing(facts[0], draft: draft), facts[1]])))
        }
        for bytes in [Data(), Data("{}".utf8), try F.bytes("wrong", source: .morning), try F.bytes("A", source: .evening)] {
            XCTAssertThrowsError(try F.snapshot(F.input(facts: [F.replacing(facts[0], local: .persisted(payload: bytes, readOnly: false))])))
        }
    }

    func testStableVersionsExactCommentAndInputOrdering() throws {
        let input = try F.input()
        let first = try F.snapshot(input)
        let reverse = try F.snapshot(F.input(facts: input.itemFacts.reversed()))
        XCTAssertEqual(first, reverse)
        var versions = Set<DayComposerSourceVersion>()
        for comment in ["", " ", "text", "text "] {
            let snapshot = try F.snapshot(F.input(comment: comment))
            versions.insert(snapshot.sourceVersion)
            XCTAssertEqual(snapshot.exerciseVersions, first.exerciseVersions)
        }
        XCTAssertEqual(versions.count, 4)
        XCTAssertEqual(first.payloads[input.itemFacts[0].itemID], input.itemFacts[0].local.payload)
    }

    func testSnapshotRelations() throws {
        let snapshot = try F.snapshot(F.input())
        XCTAssertEqual(snapshot.relation(to: try F.input()), .current)
        XCTAssertEqual(snapshot.relation(to: try F.input(comment: "changed")), .stale)
        XCTAssertEqual(snapshot.relation(to: try F.input(revision: 1)), .revalidationRequired)
        XCTAssertEqual(snapshot.relation(to: try F.input(source: .evening)), .contextMismatch)
        XCTAssertEqual(snapshot.relation(to: try F.input(stabilization: .unknown)), .unknown)
    }

    func testObservationOnlySnapshotHasNoFakeDependencies() throws {
        let snapshot = try F.snapshot(F.input(facts: [], observed: ["A", "B"]))
        XCTAssertTrue(snapshot.exerciseVersions.isEmpty)
        XCTAssertTrue(snapshot.payloads.isEmpty)
        XCTAssertEqual(snapshot.sourceVersion.orderedItems.count, 2)
    }

    func testCompletionUnknownAndContextFreshnessPreventReady() throws {
        XCTAssertNotEqual(DayComposerReadiness.evaluate(try F.input(completion: .unknown)).state, .ready)
        XCTAssertNotEqual(DayComposerReadiness.evaluate(try F.input(contextFreshness: .stale)).state, .ready)
    }
}
