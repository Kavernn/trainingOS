import XCTest
@testable import TrainingOS

@MainActor
final class DayComposerProductFlowTests: XCTestCase {
    func testStartRequiresCurrentCompleteUnambiguousQueue() throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        let s = r.fixture.coordinator.input.snapshot
        let reordered = Array(s.initialUnits.reversed()).flatMap { $0.items.map(\.id) }
        XCTAssertTrue(s.canStart(orderedIDs: reordered, activeProgram: s.activeProgramID, date: s.date,
            loading: false, incompatible: false))
        for (program, date, loading, incompatible) in [
            ("inactive", s.date, false, false), (s.activeProgramID, "2000-01-01", false, false),
            (s.activeProgramID, s.date, true, false), (s.activeProgramID, s.date, false, true)
        ] {
            XCTAssertFalse(s.canStart(orderedIDs: reordered, activeProgram: program, date: date,
                loading: loading, incompatible: incompatible))
        }
        XCTAssertFalse(s.canStart(orderedIDs: [], activeProgram: s.activeProgramID, date: s.date,
            loading: false, incompatible: false))
        XCTAssertEqual(s.units(for: reordered)?.flatMap { $0.items.map(\.id) }, reordered)
        XCTAssertEqual(Set(reordered.map(\.source)), Set([.morning, .evening]))
    }

    func testExplicitRPEFinishCompletesSourcesIndependentlyWithoutTemplateMutation() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        let original = r.fixture.coordinator.input.snapshot
        await r.engine.finishSource(.morning, rpe: 8)
        XCTAssertEqual(r.engine.productState(.morning), .completed)
        XCTAssertEqual(r.engine.productState(.evening), .ready)
        XCTAssertFalse(r.engine.dayCompleted)
        XCTAssertEqual(try r.inputs.load(executionIdentity: r.fixture.coordinator.morningFinalInputs.identity,
            source: .morning)?.values.rpe, 8)
        await r.engine.finishSource(.evening, rpe: 9)
        XCTAssertTrue(r.engine.dayCompleted)
        XCTAssertEqual(try original.fingerprint, try r.fixture.coordinator.input.snapshot.fingerprint)
        XCTAssertEqual(r.fixture.coordinator.context.date, original.date)
    }

    func testInvalidRPECannotPostAndNoAutomaticFallback() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        for value in [5.0, 7.5, 11.0] {
            await r.engine.finishSource(.morning, rpe: value)
            XCTAssertEqual(r.engine.productState(.morning), .failed)
            XCTAssertTrue(r.posted.isEmpty)
        }
    }

    func testPendingRefreshNeverPostsAgainAndEveningRemainsUsable() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        r.exerciseHook = { request in
            if request.source == .morning {
                let receipt = DayComposerFinishRig.receipt(request.operationKey)
                r.statuses[request.operationKey] = .pending(receipt)
                return .queued(receipt)
            }
            r.statuses[request.operationKey] = .delivered(DayComposerFinishRig.record(request.operationKey))
            return .applicationConfirmed(DayComposerFinishRig.exerciseOK)
        }
        await r.engine.finishSource(.morning, rpe: 7)
        XCTAssertEqual(r.engine.productState(.morning), .pending)
        let before = r.posted
        await r.engine.refreshSource(.morning)
        XCTAssertEqual(r.posted, before)
        XCTAssertEqual(r.engine.productState(.morning), .pending)
        await r.engine.finishSource(.evening, rpe: 7)
        XCTAssertEqual(r.engine.productState(.evening), .completed)
        XCTAssertFalse(r.engine.dayCompleted)
    }

    func testProcessingAndReviewAreNeverPresentedAsCompleted() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        r.exerciseHook = { request in
            XCTAssertEqual(r.engine.productState(.morning), .processing)
            let record = DayComposerFinishRig.record(request.operationKey, state: .uncertain)
            r.statuses[request.operationKey] = .uncertain(record)
            return .uncertain(record)
        }
        await r.engine.finishSource(.morning, rpe: 7)
        XCTAssertEqual(r.engine.productState(.morning), .review)
        XCTAssertFalse(r.engine.dayCompleted)
        let count = r.posted.count
        await r.engine.refreshSource(.morning)
        XCTAssertEqual(r.posted.count, count)
    }
}
