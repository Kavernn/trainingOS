import XCTest
@testable import TrainingOS

@MainActor
final class DayComposerFinishCoordinatorTests: XCTestCase {
    func testBoundedSuccessAndReinvokeDoNotDuplicatePosts() async throws {
        let r = try DayComposerFinishRig(names: ["A", "B", "C"]); defer { r.cleanup() }
        let a = try r.prepare()
        let result = await r.engine.advanceSource(a)
        XCTAssertNil(result.error)
        XCTAssertEqual(result.reconciliation?.isResolved, true)
        XCTAssertEqual(r.posted, a.adapter.exercises.map(\.operationKey) + [a.adapter.finalKey])
        XCTAssertEqual(r.completionCalls, 1)
        r.serverCompletion = .completedObserved
        let again = await r.engine.advanceSource(a)
        XCTAssertEqual(again.reconciliation?.isResolved, true)
        XCTAssertEqual(r.posted.count, 4)
        XCTAssertEqual(r.completionCalls, 1)
    }

    func testExerciseTransportMatrixReconcilesBeforeChoosingAction() async throws {
        // Includes no intent, safe intent, ambiguous started/notFound and every f1 state.
        for kind in ["new", "intent", "started", "pending", "delivered", "uncertain", "discarded", "confirmed", "failure", "invalid"] {
            let r = try DayComposerFinishRig(); defer { r.cleanup() }
            let a = try r.prepare()
            let v = try XCTUnwrap(a.adapter.snapshot.exerciseVersions.first)
            let key = try v.operationKey(identity: a.reference.executionIdentity)
            if kind != "new" {
                try r.store.recordExerciseIntent(identity: a.reference.executionIdentity, version: v)
                if kind != "intent" {
                    try r.store.markSubmissionMayHaveStarted(identity: a.reference.executionIdentity, operationKey: key)
                }
            }
            switch kind {
            case "pending": r.statuses[key] = .pending(DayComposerFinishRig.receipt(key))
            case "delivered": r.statuses[key] = .delivered(DayComposerFinishRig.record(key))
            case "uncertain": r.statuses[key] = .uncertain(DayComposerFinishRig.record(key, state: .uncertain))
            case "discarded": r.statuses[key] = .discarded(DayComposerFinishRig.record(key, state: .discarded))
            case "confirmed", "failure", "invalid":
                r.statuses[key] = .delivered(DayComposerFinishRig.record(key))
                try r.store.recordExerciseApplication(identity: a.reference.executionIdentity, version: v,
                    state: kind == "confirmed" ? .confirmed : kind == "failure" ? .failure : .invalidResponse)
            default: break
            }
            let result = await r.engine.advanceSource(a)
            XCTAssertNil(result.error, kind)
            XCTAssertTrue(r.queried.contains(key), kind)
            if kind == "new" || kind == "intent" {
                XCTAssertEqual(r.posted, [key, a.adapter.finalKey], kind)
            } else if kind == "confirmed" {
                XCTAssertEqual(r.posted, [a.adapter.finalKey], kind)
            } else {
                XCTAssertTrue(r.posted.isEmpty, kind)
                XCTAssertEqual(result.reconciliation?.isResolved, false, kind)
            }
        }
    }

    func testDirectExerciseFailuresAndInvalidResponsesAreDurable() async throws {
        for invalid in [false, true] {
            let r = try DayComposerFinishRig(); defer { r.cleanup() }
            let a = try r.prepare()
            r.exerciseHook = { request in
                r.statuses[request.operationKey] = .delivered(DayComposerFinishRig.record(request.operationKey))
                return invalid ? .invalidResponse : .applicationFailure
            }
            _ = await r.engine.advanceSource(a)
            let v = try XCTUnwrap(a.adapter.snapshot.exerciseVersions.first)
            XCTAssertEqual(try r.store.exerciseEvidence(identity: a.reference.executionIdentity, version: v),
                invalid ? .invalidResponse : .failure)
            XCTAssertEqual(r.posted.count, 1)
            _ = await r.engine.advanceSource(a)
            XCTAssertEqual(r.posted.count, 1)
        }
    }

    func testABConfirmedCQueuedStopsFinalAndRetrySkipsAB() async throws {
        let r = try DayComposerFinishRig(names: ["A", "B", "C"]); defer { r.cleanup() }
        let a = try r.prepare()
        r.exerciseHook = { request in
            if request.itemIdentity == "C" {
                let receipt = DayComposerFinishRig.receipt(request.operationKey)
                r.statuses[request.operationKey] = .pending(receipt)
                return .queued(receipt)
            }
            r.statuses[request.operationKey] = .delivered(DayComposerFinishRig.record(request.operationKey))
            return .applicationConfirmed(DayComposerFinishRig.exerciseOK)
        }
        let first = await r.engine.advanceSource(a)
        XCTAssertEqual(first.reconciliation?.hasPending, true)
        XCTAssertEqual(r.posted, a.adapter.exercises.map(\.operationKey))
        let second = await r.engine.advanceSource(a)
        XCTAssertEqual(second.reconciliation?.canSubmitFinal, false)
        XCTAssertEqual(r.posted.count, 3)
        XCTAssertEqual(r.completionCalls, 0)
    }

    func testFinalOutcomesCompletionAndNoDuplicateFinal() async throws {
        for kind in ["confirmed", "queued", "failure", "invalid", "delivered", "uncertain", "discarded"] {
            for observation in [SourceCompletionObservation.observed, .unconfirmed, .lookupFailure, .unsupportedDate] {
                let r = try DayComposerFinishRig(); defer { r.cleanup() }
                let a = try r.prepare()
                r.completion = observation
                r.finalHook = { request in
                    let key = request.operationKey
                    switch kind {
                    case "queued":
                        let receipt = DayComposerFinishRig.receipt(key)
                        r.statuses[key] = .pending(receipt); return .queued(receipt)
                    case "uncertain":
                        let record = DayComposerFinishRig.record(key, state: .uncertain)
                        r.statuses[key] = .uncertain(record); return .uncertain(record)
                    case "discarded":
                        let record = DayComposerFinishRig.record(key, state: .discarded)
                        r.statuses[key] = .discarded(record); return .discarded(record)
                    default:
                        let record = DayComposerFinishRig.record(key)
                        r.statuses[key] = .delivered(record)
                        if kind == "failure" { return .applicationFailure }
                        if kind == "invalid" { return .invalidResponse }
                        if kind == "delivered" { return .transportDeliveredUnverified(record) }
                        return .applicationConfirmed(.init(success: true))
                    }
                }
                let first = await r.engine.advanceSource(a)
                XCTAssertEqual(first.reconciliation?.isResolved, kind == "confirmed" && observation == .observed, kind)
                XCTAssertEqual(r.completionCalls, kind == "confirmed" || kind == "delivered" ? 1 : 0)
                _ = await r.engine.advanceSource(a)
                XCTAssertEqual(r.posted.filter { $0 == a.adapter.finalKey }.count, 1, kind)
                if kind == "delivered" {
                    XCTAssertEqual(try r.store.finalEvidence(identity: a.reference.executionIdentity,
                        sourceVersion: a.reference.sourceVersion, finalPayloadVersion: a.adapter.finalVersion), .unknown)
                }
            }
        }
    }

    func testStaleDuringExerciseAwaitPersistsOldACKAndStops() async throws {
        let r = try DayComposerFinishRig(names: ["A", "B"]); defer { r.cleanup() }
        let a = try r.prepare()
        r.exerciseHook = { request in
            XCTAssertTrue(r.fixture.barrier.editComment(r.fixture.morning, text: "S2"))
            _ = try? r.prepare()
            r.statuses[request.operationKey] = .delivered(DayComposerFinishRig.record(request.operationKey))
            return .applicationConfirmed(DayComposerFinishRig.exerciseOK)
        }
        let result = await r.engine.advanceSource(a)
        XCTAssertEqual(result.error, .staleSnapshot)
        XCTAssertEqual(r.posted.count, 1)
        let v = try XCTUnwrap(a.adapter.snapshot.exerciseVersions.first {
            (try? $0.operationKey(identity: a.reference.executionIdentity)) == r.posted.first
        })
        XCTAssertEqual(try r.store.exerciseEvidence(identity: a.reference.executionIdentity, version: v), .confirmed)
    }

    func testPrivateEditorEditWithoutG2ChangeExpiresArtifact() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        let a = try r.prepare()
        let guardBefore = try r.fixture.coordinator.currentFinalizationGuard(for: .morning)
        r.exerciseHook = { request in
            r.fixture.handles.first?.signal(identity: "pending-note", unresolved: "editing")
            r.statuses[request.operationKey] = .delivered(DayComposerFinishRig.record(request.operationKey))
            return .applicationConfirmed(DayComposerFinishRig.exerciseOK)
        }
        let result = await r.engine.advanceSource(a)
        XCTAssertEqual(try r.fixture.coordinator.currentFinalizationGuard(for: .morning), guardBefore)
        XCTAssertEqual(result.error, .staleSnapshot)
        XCTAssertEqual(r.posted.count, 1)
    }

    func testStaleDuringFinalAwaitStoresOldFinalACK() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        let a = try r.prepare()
        r.finalHook = { request in
            _ = try? r.fixture.coordinator.setFinalRPE(8, for: .morning)
            r.statuses[request.operationKey] = .delivered(DayComposerFinishRig.record(request.operationKey))
            return .applicationConfirmed(.init(success: true))
        }
        let result = await r.engine.advanceSource(a)
        XCTAssertEqual(result.error, .staleSnapshot)
        XCTAssertEqual(try r.store.finalEvidence(identity: a.reference.executionIdentity,
            sourceVersion: a.reference.sourceVersion, finalPayloadVersion: a.adapter.finalVersion), .confirmed)
        XCTAssertEqual(r.completionCalls, 0)
    }

    func testHistoricalExerciseABAIsNotReused() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        let a = try r.prepare()
        let v1 = try XCTUnwrap(a.adapter.snapshot.exerciseVersions.first)
        try r.store.recordExerciseIntent(identity: a.reference.executionIdentity, version: v1)
        let key1 = try v1.operationKey(identity: a.reference.executionIdentity)
        try r.store.markSubmissionMayHaveStarted(identity: a.reference.executionIdentity, operationKey: key1)
        try r.store.recordExerciseApplication(identity: a.reference.executionIdentity, version: v1, state: .confirmed)
        let v2 = try DayComposerExerciseVersion(itemID: v1.itemID, date: a.reference.executionIdentity.date,
            payloadData: Data("different exact historical bytes".utf8))
        try r.store.recordExerciseIntent(identity: a.reference.executionIdentity, version: v2)
        let key2 = try v2.operationKey(identity: a.reference.executionIdentity)
        try r.store.markSubmissionMayHaveStarted(identity: a.reference.executionIdentity, operationKey: key2)
        let result = await r.engine.advanceSource(a)
        XCTAssertTrue(r.queried.contains(key2))
        XCTAssertEqual(result.reconciliation?.requiresReview, true)
        XCTAssertTrue(r.posted.isEmpty)
    }

    func testCommentOnlyRecaptureReusesExerciseACKs() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        let a = try r.prepare()
        let v = try XCTUnwrap(a.adapter.snapshot.exerciseVersions.first)
        let key = try v.operationKey(identity: a.reference.executionIdentity)
        try r.store.recordExerciseIntent(identity: a.reference.executionIdentity, version: v)
        try r.store.markSubmissionMayHaveStarted(identity: a.reference.executionIdentity, operationKey: key)
        try r.store.recordExerciseApplication(identity: a.reference.executionIdentity, version: v, state: .confirmed)
        XCTAssertTrue(r.fixture.barrier.editComment(r.fixture.morning, text: "new comment"))
        let b = try r.prepare()
        let result = await r.engine.advanceSource(b)
        XCTAssertEqual(result.reconciliation?.isResolved, true)
        XCTAssertEqual(r.posted, [b.adapter.finalKey])
    }

    func testMorningQueuedDoesNotBlockEvening() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        let am = try r.prepare(.morning), pm = try r.prepare(.evening)
        r.exerciseHook = { request in
            if request.source == .morning {
                let receipt = DayComposerFinishRig.receipt(request.operationKey)
                r.statuses[request.operationKey] = .pending(receipt); return .queued(receipt)
            }
            r.statuses[request.operationKey] = .delivered(DayComposerFinishRig.record(request.operationKey))
            return .applicationConfirmed(DayComposerFinishRig.exerciseOK)
        }
        let morning = await r.engine.advanceSource(am)
        let evening = await r.engine.advanceSource(pm)
        XCTAssertEqual(morning.reconciliation?.hasPending, true)
        XCTAssertEqual(evening.reconciliation?.isResolved, true)
    }

    func testGlobalContextAndWrongDateRefuseTransport() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        let am = try r.prepare(.morning), pm = try r.prepare(.evening)
        r.serverOverride = .init(source: .morning, date: "2000-01-01", freshness: .fresh,
            observedNames: [], completion: .notCompleted)
        let wrongDate = await r.engine.advanceSource(am)
        XCTAssertEqual(wrongDate.error, .contextRejected)
        r.fixture.coordinator.reportPersistenceRefusal(.rejectedContext)
        let morning = await r.engine.advanceSource(am), evening = await r.engine.advanceSource(pm)
        XCTAssertEqual(morning.error, .contextRejected); XCTAssertEqual(evening.error, .contextRejected)
        XCTAssertTrue(r.posted.isEmpty)
    }

    func testSameSourceBusyAndCancellationPreserveMarker() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        let a = try r.prepare()
        var continuation: CheckedContinuation<Void, Never>?
        let entered = expectation(description: "transport entered")
        r.exerciseHook = { _ in
            await withCheckedContinuation { continuation = $0; entered.fulfill() }
            return .failedBeforeSubmission("cancelled after durable marker")
        }
        let first = Task { await r.engine.advanceSource(a) }
        await fulfillment(of: [entered], timeout: 2)
        let duplicate = await r.engine.advanceSource(a)
        XCTAssertEqual(duplicate.error, .busy)
        first.cancel(); continuation?.resume()
        let cancelled = await first.value
        XCTAssertEqual(cancelled.error, .cancelled)
        XCTAssertEqual(r.engine.phases[.morning], .idle)
        let next = await r.engine.advanceSource(a)
        XCTAssertEqual(next.reconciliation?.requiresReview, true)
        XCTAssertEqual(r.posted.count, 1)
        let record = try XCTUnwrap(r.store.load(identity: a.reference.executionIdentity))
        XCTAssertEqual(record.exerciseIntents.first?.submissionPhase, .submissionMayHaveStarted)
    }

    func testFinalIntentNotFoundIsSafeOnlyBeforeAttemptMarker() async throws {
        for started in [false, true] {
            let r = try DayComposerFinishRig(); defer { r.cleanup() }
            let a = try r.prepare()
            for version in a.adapter.snapshot.exerciseVersions {
                let key = try version.operationKey(identity: a.reference.executionIdentity)
                try r.store.recordExerciseIntent(identity: a.reference.executionIdentity, version: version)
                try r.store.markSubmissionMayHaveStarted(identity: a.reference.executionIdentity, operationKey: key)
                try r.store.recordExerciseApplication(identity: a.reference.executionIdentity, version: version, state: .confirmed)
            }
            try r.store.recordFinalIntent(identity: a.reference.executionIdentity, sourceVersion: a.reference.sourceVersion,
                finalPayloadVersion: a.adapter.finalVersion, provenanceGuard: a.reference.provenanceGuard)
            if started {
                try r.store.markSubmissionMayHaveStarted(identity: a.reference.executionIdentity, operationKey: a.adapter.finalKey)
            }
            let result = await r.engine.advanceSource(a)
            XCTAssertEqual(r.posted, started ? [] : [a.adapter.finalKey])
            XCTAssertEqual(result.reconciliation?.isResolved, !started)
        }
    }

    func testFinalRPEABAConsultsHistoricalPotentiallyEffectfulKey() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        let a = try r.prepare()
        for version in a.adapter.snapshot.exerciseVersions {
            let key = try version.operationKey(identity: a.reference.executionIdentity)
            try r.store.recordExerciseIntent(identity: a.reference.executionIdentity, version: version)
            try r.store.markSubmissionMayHaveStarted(identity: a.reference.executionIdentity, operationKey: key)
            try r.store.recordExerciseApplication(identity: a.reference.executionIdentity, version: version, state: .confirmed)
        }
        try r.fixture.coordinator.setFinalRPE(8, for: .morning)
        let b = try r.prepare()
        try r.store.recordFinalIntent(identity: b.reference.executionIdentity, sourceVersion: b.reference.sourceVersion,
            finalPayloadVersion: b.adapter.finalVersion, provenanceGuard: b.reference.provenanceGuard)
        try r.store.markSubmissionMayHaveStarted(identity: b.reference.executionIdentity, operationKey: b.adapter.finalKey)
        try r.fixture.coordinator.setFinalRPE(7, for: .morning)
        let returned = try r.prepare()
        let result = await r.engine.advanceSource(returned)
        XCTAssertEqual(returned.adapter.finalKey, a.adapter.finalKey)
        XCTAssertTrue(r.queried.contains(b.adapter.finalKey))
        XCTAssertEqual(result.reconciliation?.requiresReview, true)
        XCTAssertTrue(r.posted.isEmpty)
    }

    func testIntentOrAttemptMarkerWriteFailurePreventsTransport() async throws {
        for rejectMarkerOnly in [false, true] {
            let r = try DayComposerFinishRig(writer: { data, url in
                let record = try JSONDecoder().decode(DayComposerFinalizationRecord.self, from: data)
                let forbidden = rejectMarkerOnly
                    ? record.exerciseIntents.contains { $0.submissionPhase == .submissionMayHaveStarted }
                    : !record.exerciseIntents.isEmpty
                if forbidden { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: url, options: .atomic)
            })
            defer { r.cleanup() }
            let a = try r.prepare()
            let result = await r.engine.advanceSource(a)
            XCTAssertEqual(result.error, .durabilityFailure)
            XCTAssertTrue(r.posted.isEmpty)
        }
    }
}
