import Foundation
import XCTest
#if canImport(TrainingOS)
@testable import TrainingOS
#endif

final class DayComposerFinalizationReconciliationTests: XCTestCase {
    private typealias F = FinalizationFactsFixture
    private typealias R = DayComposerFinalizationReconciliation

    func testExerciseDependencyStates() throws {
        let snapshot = try F.snapshot(F.input())
        let version = snapshot.exerciseVersions[0]
        XCTAssertEqual(R.exercise(version, snapshot: snapshot, history: try F.input().history), .notSubmitted)
        let cases: [(DayComposerApplicationState, DayComposerSubmissionPhase, DayComposerTransportFact, DayComposerExerciseDependencyState)] = [
            (.confirmed, .submissionMayHaveStarted, .delivered, .applicationConfirmed),
            (.confirmed, .submissionMayHaveStarted, .notFound, .applicationConfirmed),
            (.unknown, .submissionMayHaveStarted, .pending, .pending),
            (.unknown, .submissionMayHaveStarted, .delivered, .deliveredUnverified),
            (.unknown, .submissionMayHaveStarted, .discarded, .discarded),
            (.unknown, .submissionMayHaveStarted, .uncertain, .uncertain),
            (.unknown, .submissionMayHaveStarted, .notFound, .uncertain),
            (.unknown, .intentRecorded, .notFound, .notSubmitted),
            (.failure, .submissionMayHaveStarted, .delivered, .applicationFailure),
            (.invalidResponse, .submissionMayHaveStarted, .delivered, .invalidResponse),
            (.confirmed, .submissionMayHaveStarted, .pending, .staleOrConflicting)]
        for (application, phase, transport, expected) in cases {
            let history = try F.history(F.record(snapshot, application: application, phase: phase), transport: transport)
            XCTAssertEqual(R.exercise(version, snapshot: snapshot, history: history), expected)
        }
        let missingLookup = DayComposerFinalizationHistory(durability: .trusted, current: nil, candidates: [], transports: [:])
        XCTAssertEqual(R.exercise(version, snapshot: snapshot, history: missingLookup), .uncertain)
    }

    func testDifferentVersionAndForeignContextRejected() throws {
        let am = try F.snapshot(F.input()), pm = try F.snapshot(F.input(source: .evening))
        XCTAssertEqual(R.exercise(pm.exerciseVersions[0], snapshot: am, history: try F.input().history), .staleOrConflicting)
        let plan = try F.plan()
        let foreign = try DayComposerFinalizationRecord(identity: F.identity(plan, execution: UUID()), now: F.instant)
        XCTAssertEqual(R.exercise(am.exerciseVersions[0], snapshot: am, history: F.history(foreign)), .durabilityBlocked)
    }

    func testABAMarkerTransportAndApplicationEvidenceBlockReuse() throws {
        let input = try F.input(), snapshot = try F.snapshot(input)
        let e1 = snapshot.exerciseVersions[0]
        let e2 = try DayComposerExerciseVersion(itemID: e1.itemID, date: F.date, payloadData: F.bytes("A", source: .morning, reps: "9"))
        let cases: [(DayComposerSubmissionPhase, DayComposerApplicationState, DayComposerTransportFact)] = [
            (.submissionMayHaveStarted, .unknown, .notFound), (.submissionMayHaveStarted, .unknown, .pending),
            (.submissionMayHaveStarted, .unknown, .delivered), (.submissionMayHaveStarted, .confirmed, .delivered),
            (.intentRecorded, .unknown, .pending), (.intentRecorded, .unknown, .notLookedUp)]
        for (phase, application, transport) in cases {
            var record = try F.record(snapshot)
            var other = try DayComposerExerciseIntentRecord(identity: input.identity, version: e2, now: F.instant)
            other.submissionPhase = phase
            other.applicationEvidence = application == .unknown ? nil : application
            // Deliberately earlier timestamps: never use them as causal proof.
            other.updatedAt = F.instant.addingTimeInterval(-100)
            record.exerciseIntents.append(other)
            let base = F.history(record)
            var transports = base.transports
            transports[other.operationKey] = transport
            let history = DayComposerFinalizationHistory(durability: .trusted, current: record, candidates: [], transports: transports)
            XCTAssertEqual(R.exercise(e1, snapshot: snapshot, history: history), .staleOrConflicting)
        }
    }

    func testABAUnsentCompetingIntentDoesNotInvalidateE1() throws {
        let snapshot = try F.snapshot(F.input())
        var record = try F.record(snapshot)
        let e2 = try DayComposerExerciseVersion(itemID: snapshot.exerciseVersions[0].itemID, date: F.date,
            payloadData: F.bytes("A", source: .morning, reps: "9"))
        let other = try DayComposerExerciseIntentRecord(identity: snapshot.identity, version: e2, now: F.instant)
        record.exerciseIntents.append(other)
        var transports = F.history(record).transports
        transports[other.operationKey] = .notFound
        let history = DayComposerFinalizationHistory(durability: .trusted, current: record, candidates: [], transports: transports)
        XCTAssertEqual(R.exercise(snapshot.exerciseVersions[0], snapshot: snapshot, history: history), .applicationConfirmed)
    }

    func testCommentOnlyReusesExerciseButNeverFinalEvidence() throws {
        let a = try F.snapshot(F.input(comment: "A")), b = try F.snapshot(F.input(comment: "B"))
        let history = try F.history(F.record(a, final: true))
        XCTAssertEqual(a.exerciseVersions, b.exerciseVersions)
        XCTAssertNotEqual(a.sourceVersion, b.sourceVersion)
        for version in b.exerciseVersions { XCTAssertEqual(R.exercise(version, snapshot: b, history: history), .applicationConfirmed) }
        XCTAssertEqual(R.final(snapshot: b, history: history, payload: try F.finalPayload(), completion: .notCompleted).state, .stale)
    }

    func testDependencyAggregationAndPriority() throws {
        let ids = try F.snapshot(F.input()).exerciseVersions.map(\.itemID)
        let cases: [(DayComposerExerciseDependencyState, NeutralSourceDependencies)] = [
            (.applicationConfirmed, .satisfied), (.pending, .waiting), (.deliveredUnverified, .unverified),
            (.notSubmitted, .unverified), (.uncertain, .uncertain), (.discarded, .failed),
            (.applicationFailure, .failed), (.invalidResponse, .failed), (.staleOrConflicting, .failed), (.durabilityBlocked, .failed)]
        for (state, expected) in cases {
            XCTAssertEqual(DayComposerSourceDependencies(items: [ids[0]: .applicationConfirmed, ids[1]: state]).state, expected)
        }
        XCTAssertEqual(DayComposerSourceDependencies(items: [ids[0]: .pending, ids[1]: .deliveredUnverified]).state, .unverified)
        XCTAssertEqual(DayComposerSourceDependencies(items: [ids[0]: .uncertain, ids[1]: .discarded]).state, .failed)
    }

    func testFinalStatesAndOfflineCompletionNeverPromotesApplication() throws {
        let snapshot = try F.snapshot(F.input())
        let cases: [(DayComposerApplicationState, DayComposerSubmissionPhase, DayComposerTransportFact,
                     DayComposerSourceCompletion, DayComposerFinalOperationState.State)] = [
            (.unknown, .intentRecorded, .notFound, .notCompleted, .readyToSubmit),
            (.unknown, .submissionMayHaveStarted, .notFound, .notCompleted, .uncertain),
            (.unknown, .submissionMayHaveStarted, .pending, .notCompleted, .pending),
            (.unknown, .submissionMayHaveStarted, .delivered, .completedObserved, .deliveredUnverified),
            (.confirmed, .submissionMayHaveStarted, .delivered, .unknown, .applicationConfirmedCompletionUnknown),
            (.confirmed, .submissionMayHaveStarted, .delivered, .completedObserved, .completedObserved),
            (.unknown, .submissionMayHaveStarted, .discarded, .notCompleted, .discarded),
            (.unknown, .submissionMayHaveStarted, .uncertain, .notCompleted, .uncertain),
            (.failure, .submissionMayHaveStarted, .delivered, .notCompleted, .applicationFailure),
            (.invalidResponse, .submissionMayHaveStarted, .delivered, .notCompleted, .invalidResponse)]
        for (app, phase, transport, completion, expected) in cases {
            let history = try F.history(F.record(snapshot, application: app, phase: phase, final: true), transport: transport)
            let state = R.final(snapshot: snapshot, history: history, payload: try F.finalPayload(), completion: completion)
            XCTAssertEqual(state.state, expected)
            XCTAssertEqual(state.application, app)
            XCTAssertEqual(state.completion, completion)
        }
        XCTAssertEqual(R.final(snapshot: snapshot, history: try F.input().history, payload: nil, completion: .notCompleted).state, .notPrepared)
    }

    func testRetryMatrixAToL() throws {
        let snapshot = try F.snapshot(F.input())
        let payload = try F.finalPayload()
        let finalKey = try payload.operationKey(identity: snapshot.identity, sourceVersion: snapshot.sourceVersion)
        let noIntent = F.history(nil, extra: try F.input().history.transports.merging([finalKey: .notFound]) { _, new in new })
        XCTAssertEqual(R.source(try F.input(history: noIntent), finalPayload: payload).retry, .prepareAndSubmit) // A
        let cases: [(DayComposerApplicationState, DayComposerSubmissionPhase, DayComposerTransportFact, DayComposerRetryDecision)] = [
            (.unknown, .intentRecorded, .notFound, .resumeIntent), // B
            (.unknown, .submissionMayHaveStarted, .notFound, .reviewRequired), // C: never infer expired vs unsent
            (.unknown, .submissionMayHaveStarted, .pending, .wait), // D
            (.unknown, .submissionMayHaveStarted, .delivered, .refreshOnly), // E
            (.unknown, .submissionMayHaveStarted, .discarded, .reviewRequired), // F
            (.unknown, .submissionMayHaveStarted, .uncertain, .refreshOnly), // G
            (.confirmed, .submissionMayHaveStarted, .delivered, .refreshOnly), // H
            (.failure, .submissionMayHaveStarted, .delivered, .reviewRequired), // I
            (.invalidResponse, .submissionMayHaveStarted, .delivered, .reviewRequired)] // J
        for (app, phase, transport, expected) in cases {
            // Final state varies; exercise dependencies remain confirmed.
            var record = try F.record(snapshot, final: true)
            record.finalIntents[0].submissionPhase = phase
            record.finalIntents[0].applicationState = app
            var transports = F.history(record).transports
            transports[finalKey] = transport
            let history = DayComposerFinalizationHistory(durability: .trusted, current: record, candidates: [], transports: transports)
            XCTAssertEqual(R.source(try F.input(history: history), finalPayload: payload).retry, expected)
        }
        let historical = try F.history(F.record(snapshot, final: true))
        XCTAssertEqual(R.source(try F.input(comment: "changed", history: historical), finalPayload: payload).retry, .reviewRequired) // K
        XCTAssertEqual(R.source(try F.input(comment: "changed", completion: .completedObserved, history: historical),
            finalPayload: payload).retry, .reviewRequired) // L
    }

    func testOldCandidateStatesAndNoEvidenceAdoption() throws {
        let input = try F.input(), snapshot = try F.snapshot(input)
        let oldID = try F.identity(F.plan(), execution: UUID(uuidString: "00000000-0000-4000-8000-000000000099")!)
        let cases: [(DayComposerSubmissionPhase, DayComposerApplicationState, DayComposerTransportFact, DayComposerOldCandidateImpact)] = [
            (.intentRecorded, .unknown, .notFound, .irrelevantHistorical),
            (.submissionMayHaveStarted, .unknown, .notFound, .blocksCurrent),
            (.submissionMayHaveStarted, .unknown, .pending, .blocksCurrent),
            (.submissionMayHaveStarted, .unknown, .delivered, .requiresReview),
            (.submissionMayHaveStarted, .confirmed, .delivered, .historicalResolvedFact)]
        for (phase, app, transport, expected) in cases {
            var candidate = try DayComposerFinalizationRecord(identity: oldID, now: F.instant)
            var intent = try DayComposerExerciseIntentRecord(identity: oldID, version: snapshot.exerciseVersions[0], now: F.instant)
            intent.submissionPhase = phase
            intent.applicationEvidence = app == .unknown ? nil : app
            candidate.exerciseIntents = [intent]
            let history = F.history(nil, transport: transport, candidates: [candidate], extra: input.history.transports)
            XCTAssertEqual(R.candidate(candidate, identity: input.identity, source: .morning, history: history), expected)
            XCTAssertEqual(R.candidate(candidate, identity: input.identity, source: .evening, history: history), .irrelevantHistorical)
            let dependency = R.exercise(snapshot.exerciseVersions[0], snapshot: snapshot, history: history)
            XCTAssertEqual(dependency, expected == .irrelevantHistorical ? .notSubmitted : .staleOrConflicting)
        }
    }

    func testAbsentCorruptRecordsCandidateScanAndWriteFailure() throws {
        XCTAssertTrue(R.source(try F.input()).isFinalizable)
        for durability in [DayComposerDurabilityFact.unavailable, .corruptCurrent, .corruptCandidates, .writeFailed] {
            let input = try F.input(history: F.history(nil, durability: durability))
            XCTAssertEqual(R.source(input).retry, .blocked)
        }
        let snapshot = try F.snapshot(F.input())
        var corrupt = try F.record(snapshot)
        corrupt.exerciseIntents.append(corrupt.exerciseIntents[0])
        XCTAssertEqual(R.source(try F.input(history: F.history(corrupt))).globalBlock, .durability)
        XCTAssertEqual(R.source(try F.input(history: F.history(nil, candidates: [corrupt]))).globalBlock, .candidateScan)
    }

    func testOldPendingVersionCannotHideBehindObservedOnlySnapshot() throws {
        let snapshot = try F.snapshot(F.input())
        let history = try F.history(F.record(snapshot, application: .unknown), transport: .pending)
        let state = R.source(try F.input(facts: [], observed: ["A", "B"], history: history))
        XCTAssertFalse(state.isFinalizable)
        XCTAssertFalse(state.isResolved)
        XCTAssertEqual(state.retry, .reviewRequired)
    }

    private func state(_ kind: String, source: DayComposerSource) throws -> DayComposerSourceFinishState {
        let base = try F.input(source: source)
        switch kind {
        case "ready": return R.source(base)
        case "partial": return R.source(try F.input(source: source, facts: [base.itemFacts[0]]))
        case "completed": return R.source(try F.input(source: source, facts: [], completion: .completedObserved))
        case "dirty": return R.source(try F.input(source: source, comment: "new", completion: .completedObserved))
        case "pending", "uncertain":
            let history = try F.history(F.record(F.snapshot(base), application: .unknown), transport: kind == "pending" ? .pending : .uncertain)
            return R.source(try F.input(source: source, history: history))
        default: XCTFail("Unknown fixture"); return R.source(base)
        }
    }

    func testSevenMixedCompositeStates() throws {
        let cases: [(String, String, Bool, Bool)] = [("ready", "ready", true, false), ("ready", "partial", true, false),
            ("partial", "partial", false, false), ("completed", "ready", true, false),
            ("dirty", "ready", true, true), ("pending", "ready", true, false), ("uncertain", "ready", true, true)]
        for (am, pm, eligible, review) in cases {
            let composite = try DayComposerCompositeFinishState(morning: state(am, source: .morning), evening: state(pm, source: .evening))
            XCTAssertEqual(composite.hasFinalizableSource, eligible)
            XCTAssertEqual(composite.hasReviewRequired, review)
            XCTAssertFalse(composite.allRequiredSourcesResolved)
            XCTAssertEqual(composite.hasPending, am == "pending")
        }
    }

    func testAllResolvedAndOfflineDoubleDeliveredIsNotResolved() throws {
        let clean = try DayComposerCompositeFinishState(morning: state("completed", source: .morning), evening: state("completed", source: .evening))
        XCTAssertTrue(clean.allRequiredSourcesResolved)
        XCTAssertTrue(clean.canDismiss)
        for application in [DayComposerApplicationState.unknown, .confirmed] {
            func finished(_ source: DayComposerSource) throws -> DayComposerSourceFinishState {
                let snapshot = try F.snapshot(F.input(source: source))
                var record = try F.record(snapshot, final: true)
                record.finalIntents[0].applicationState = application
                return R.source(try F.input(source: source, completion: .completedObserved, history: F.history(record)), finalPayload: try F.finalPayload())
            }
            let composite = try DayComposerCompositeFinishState(morning: finished(.morning), evening: finished(.evening))
            XCTAssertEqual(composite.allRequiredSourcesResolved, application == .confirmed)
        }
    }

    func testGlobalBlockSuppressesOtherSourceButLocalFailureDoesNot() throws {
        let pm = try state("ready", source: .evening)
        let blocked = R.source(try F.input(history: F.history(nil, durability: .writeFailed)))
        XCTAssertFalse(DayComposerCompositeFinishState(morning: blocked, evening: pm).hasFinalizableSource)
        let badContext = R.source(try F.input(provenance: false))
        XCTAssertFalse(DayComposerCompositeFinishState(morning: badContext, evening: pm).hasFinalizableSource)
        let localFailure = R.source(try F.input(history: F.history(F.record(F.snapshot(F.input()), application: .failure))))
        XCTAssertTrue(DayComposerCompositeFinishState(morning: localFailure, evening: pm).hasFinalizableSource)
    }

    func testFinalGateRequiresConfirmedDependenciesAndExplicitFinalInputs() throws {
        let input = try F.input(), snapshot = try F.snapshot(input), payload = try F.finalPayload()
        let key = try payload.operationKey(identity: snapshot.identity, sourceVersion: snapshot.sourceVersion)
        XCTAssertFalse(R.source(input).canSubmitFinal)
        let unsubmitted = F.history(nil, extra: input.history.transports.merging([key: .notFound]) { _, new in new })
        XCTAssertFalse(R.source(try F.input(history: unsubmitted), finalPayload: payload).canSubmitFinal)
        let confirmed = try F.history(F.record(snapshot), extra: [key: .notFound])
        XCTAssertTrue(R.source(try F.input(history: confirmed), finalPayload: payload).canSubmitFinal)
    }

    func testReopenReadsStoredFinalWithoutReconstructingPrivateInputs() throws {
        let snapshot = try F.snapshot(F.input())
        let history = try F.history(F.record(snapshot, final: true))
        let state = R.source(try F.input(completion: .completedObserved, history: history))
        XCTAssertTrue(state.isResolved)
        XCTAssertFalse(state.finalInputsAvailable)
        XCTAssertFalse(state.canSubmitFinal)
        let unconfirmed = R.source(try F.input(history: history))
        XCTAssertEqual(unconfirmed.retry, .refreshOnly)
        let lookupFailed = R.source(try F.input(completion: .unknown, history: history))
        XCTAssertEqual(lookupFailed.retry, .refreshOnly)
        XCTAssertFalse(lookupFailed.isResolved)
    }

    func testSnapshotAloneIsNotCompletedLocalAcknowledgment() throws {
        let snapshot = try F.snapshot(F.input())
        let record = try F.record(snapshot) // Exercises confirmed, no final ACK.
        let state = R.source(try F.input(completion: .completedObserved, history: F.history(record)))
        XCTAssertEqual(state.readiness.state, .reviewRequired)
        XCTAssertFalse(state.isResolved)
    }

    func testFailedCanonicalCaptureNeverOffersSubmission() throws {
        let plan = try F.plan()
        let invalid = try DayComposerPlan(source: .morning, session: "AM", schemes: ["": "3x8"], order: [""])
        let malformed = DayComposerSnapshot(date: F.date, activeProgramID: "program-A", morning: invalid,
            evening: plan.evening, morningCompleted: false, eveningCompleted: false)
        let id = try F.identity(malformed), guardValue = try F.guardValue()
        let input = DayComposerSourceFinalizationInput(identity: id, source: .morning, canonicalPlan: malformed,
            contextFreshness: .fresh, provenanceGuard: guardValue, provenanceCompatible: true,
            stabilization: .stableAccepted(guardValue), itemFacts: try F.facts(malformed, source: .morning), comment: "",
            server: .init(source: .morning, date: F.date, freshness: .fresh, observedNames: [], completion: .notCompleted),
            history: F.history(nil))
        XCTAssertThrowsError(try F.snapshot(input))
        XCTAssertFalse(R.source(input).isFinalizable)
        XCTAssertFalse(R.source(input).canSubmitFinal)
    }

    func testTransportValueProjectionDoesNotUpgradeDelivered() {
        let key = OfflineOperationKey(rawValue: "test-key")
        let receipt = OfflineMutationReceipt(mutationID: F.execution, operationKey: key, createdAt: F.instant)
        let record = OfflineMutationRecord(operationKey: key, receipt: receipt, state: .delivered,
            createdAt: F.instant, updatedAt: F.instant, statusCode: 200, reason: nil)
        XCTAssertEqual(DayComposerTransportFact(.notFound), .notFound)
        XCTAssertEqual(DayComposerTransportFact(.pending(receipt)), .pending)
        XCTAssertEqual(DayComposerTransportFact(.delivered(record)), .delivered)
        XCTAssertEqual(DayComposerTransportFact(.discarded(record)), .discarded)
        XCTAssertEqual(DayComposerTransportFact(.uncertain(record)), .uncertain)
    }

    func testRepeatReductionIsIdempotentAndDoesNotMutateFacts() throws {
        let input = try F.input()
        let before = try F.snapshot(input)
        for _ in 0..<20 {
            XCTAssertEqual(R.source(input), R.source(input))
            XCTAssertEqual(R.source(input).retry, .prepareAndSubmit)
            XCTAssertEqual(DayComposerReadiness.evaluate(input), DayComposerReadiness.evaluate(input))
            XCTAssertEqual(try F.snapshot(input), before)
            XCTAssertNil(input.history.current)
        }
    }
}
