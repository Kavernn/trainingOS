import XCTest
@testable import TrainingOS

@MainActor
final class DayComposerMobilityTests: XCTestCase {
    func testBinaryMobilitySetSurvivesPersistenceProjection() throws {
        // Same zero-load completion sentinel as protocol; no performed duration/reps.
        let persisted = try XCTUnwrap(PersistedSet.preserving(["weight": 0], trackingType: "mobility"))
        XCTAssertEqual(persisted.weight, 0)
        XCTAssertNil(persisted.reps)
        XCTAssertEqual(Set(persisted.payload.keys), ["weight"])
    }

    private let mobility = "90/90 Hip + Band Shoulder Rotation"
    private let strength = "A"

    func testRealPrescriptionsRemainDraftOnlyAndGroupsKeepTheirOrder() throws {
        for scheme in ["3x45s/côté", "2x5/côté", "2x10"] {
            let f = try DayComposerStabilizationFixture(morning: [mobility, strength], evening: [mobility, strength],
                tracking: [mobility: "mobility"], schemes: [mobility: scheme],
                supersets: ["AM": ["SS": .init(a: mobility, b: strength, rest: 90)]])
            defer { f.cleanup() }
            let s = f.coordinator.input.snapshot
            let order = Array(s.initialUnits.reversed()).flatMap { $0.items.map(\.id) }
            XCTAssertTrue(s.canStart(orderedIDs: order, activeProgram: s.activeProgramID, date: s.date,
                loading: false, incompatible: false))
            XCTAssertEqual(s.morning.units[0].items.map(\.name), [mobility, strength])
            XCTAssertNil(s.units(for: Array(order.reversed())))
            try f.mount(.morning)
            let vm = try XCTUnwrap(f.vms.first { $0.name == mobility })
            XCTAssertEqual(vm.scheme, scheme)
            XCTAssertEqual(vm.sets.count, 1)
            XCTAssertEqual(vm.sets[0].duration, 0)
            XCTAssertEqual(vm.sets[0].reps, "")
            XCTAssertFalse(vm.sets[0].protocolCompleted)
            XCTAssertNil(vm.buildLogCandidate(alreadyLoggedViaBinding: false))
            vm.sets[0].protocolCompleted = true
            XCTAssertTrue(f.coordinator.morningVM.logResults.isEmpty)
            XCTAssertEqual(f.coordinator.treatedCount, 0)
            f.coordinator.next()
            XCTAssertEqual(f.coordinator.treatedCount, 0)
        }
        let unknown = try DayComposerStabilizationFixture(morning: [mobility, strength],
            tracking: [mobility: "future-mobility"])
        defer { unknown.cleanup() }
        let s = unknown.coordinator.input.snapshot
        XCTAssertFalse(s.canStart(orderedIDs: s.initialIDs, activeProgram: s.activeProgramID, date: s.date,
            loading: false, incompatible: false))
    }

    func testAcceptanceCleanupProgressionUndoAndSourceIsolation() throws {
        let f = try DayComposerStabilizationFixture(morning: [mobility, strength], evening: [mobility],
            tracking: [mobility: "mobility"])
        defer { f.cleanup() }
        try f.mount(.morning)
        let vm = try XCTUnwrap(f.vms.first { $0.name == mobility })
        let id = try XCTUnwrap(f.coordinator.input.snapshot.initialIDs.first)
        vm.sets[0].protocolCompleted = true
        vm.sessionNote = "note exacte\n"
        if case .stable = vm.flushPendingLocalPersistence() {} else { XCTFail("Draft was not persisted") }
        XCTAssertEqual(vm.submitLog(alreadyLoggedViaBinding: false) { _ in .failed }, .failed)
        XCTAssertFalse(vm.isLogged)
        XCTAssertEqual(f.coordinator.treatedCount, 0)
        XCTAssertNotEqual(ExerciseDraftPersistence(date: f.date, sessionType: "morning", exerciseName: mobility).presence(), .absent)
        XCTAssertEqual(vm.submitLog(alreadyLoggedViaBinding: false) {
            f.coordinator.submit(candidate: $0, for: id)
        }, .accepted)
        XCTAssertEqual(f.coordinator.treatedCount, 0)
        XCTAssertNil(f.coordinator.eveningVM.logResults[mobility])
        XCTAssertEqual(f.coordinator.morningVM.logResults[mobility]?.notes, "note exacte\n")
        f.coordinator.advanceAfterAcceptedLog(itemID: id)
        let next = f.coordinator.currentMemberID
        f.coordinator.advanceAfterAcceptedLog(itemID: id)
        XCTAssertEqual(f.coordinator.currentMemberID, next)
        XCTAssertEqual(f.coordinator.treatedCount, 0)
        XCTAssertEqual(vm.removeAcceptedLog { _ in f.coordinator.submit(candidate: nil, for: id) }, .accepted)
        XCTAssertEqual(f.coordinator.treatedCount, 0)
        vm.isSkipped = true
        XCTAssertEqual(f.coordinator.treatedCount, 0)
    }

    func testMixedPayloadBytesVersionsAndNotesSurviveRecreationBothSources() throws {
        let r = try DayComposerFinishRig(names: [mobility, strength], tracking: [mobility: "mobility"],
            schemes: [mobility: "3x45s/côté"])
        defer { r.cleanup() }
        let before = try [DayComposerSource.morning, .evening].map { try DayComposerFinalCaptureTests.Oracle(r.prepare($0)) }
        let recreated = try DayComposerStabilizationFixture(restoring: r.fixture.coordinator.input, finalInputsStore: r.inputs)
        defer { recreated.cleanup() }
        for (index, source) in [DayComposerSource.morning, .evening].enumerated() {
            try recreated.mount(source)
            let log = try XCTUnwrap((source == .morning ? recreated.coordinator.morningVM : recreated.coordinator.eveningVM).logResults[mobility])
            XCTAssertEqual(log.notes, "exact mobilité \(source.title)\n")
            XCTAssertNil(log.rpe)
            XCTAssertEqual(log.scheme, "3x45s/côté")
            XCTAssertEqual(log.isUnilateral, false)
            XCTAssertEqual(log.sets.count, 1)
            XCTAssertEqual(Set(log.sets[0].keys), ["weight"])
            let engine = DayComposerFinishCoordinator(execution: recreated.coordinator, barrier: recreated.barrier,
                store: r.store, inputs: r.inputs,
                dependencies: .init(server: { _, s in r.server(s) }, status: { _ in .notFound },
                    exercise: { _ in XCTFail("No submission on restoration"); return .invalidResponse },
                    final: { _ in XCTFail("No finalization on restoration"); return .invalidResponse },
                    completion: { _, _ in .lookupFailure }))
            let prepared = try engine.prepareSource(source, server: r.server(source))
            XCTAssertEqual(before[index], DayComposerFinalCaptureTests.Oracle(prepared))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: prepared.adapter.finalData) as? [String: Any])
            XCTAssertFalse((json["exos"] as? [String] ?? []).contains { $0.contains(mobility) })
            XCTAssertEqual(prepared.adapter.exercises.count, 2)
        }
    }

    func testMixedFinishUsesDurableCoordinatorAndIndependentSources() async throws {
        let r = try DayComposerFinishRig(names: [mobility, strength], tracking: [mobility: "mobility"])
        defer { r.cleanup() }
        await r.engine.finishSource(.morning, rpe: 7)
        XCTAssertEqual(r.engine.productState(.morning), .completed)
        XCTAssertEqual(r.engine.productState(.evening), .ready)
        await r.engine.finishSource(.evening, rpe: 8)
        XCTAssertFalse(r.engine.dayCompleted)
        await r.engine.coaching.fetch { _ in .none }
        await r.engine.coaching.fetch { _ in .none }
        XCTAssertTrue(r.engine.dayCompleted)
        XCTAssertEqual(r.posted.count, 6) // Two exercises and one final intent per source.
    }

    func testPendingMobilityCannotConfirmOrBlindlyResend() async throws {
        let r = try DayComposerFinishRig(names: [mobility, strength], tracking: [mobility: "mobility"])
        defer { r.cleanup() }
        r.exerciseHook = { request in
            let receipt = DayComposerFinishRig.receipt(request.operationKey)
            r.statuses[request.operationKey] = .pending(receipt)
            return .queued(receipt)
        }
        await r.engine.finishSource(.morning, rpe: 7)
        XCTAssertEqual(r.engine.productState(.morning), .pending)
        let posted = r.posted
        await r.engine.refreshSource(.morning)
        XCTAssertEqual(r.posted, posted)
        XCTAssertFalse(r.engine.dayCompleted)
        XCTAssertEqual(r.completionCalls, 0)
    }

    func testMalformedMobilityIsNeitherEditableNorAccepted() throws {
        let f = try DayComposerStabilizationFixture(morning: [mobility], tracking: [mobility: "mobility"])
        defer { f.cleanup() }
        let id = f.coordinator.input.snapshot.initialIDs[0]
        var log = DayComposerFinishRig.log(mobility, source: .morning)
        log.trackingType = "mobility"
        XCTAssertNil(ExerciseRecoveryHydration.make(log, equipment: "machine", tracking: "mobility",
            unilateral: false, displayWeight: { $0 }))
        XCTAssertEqual(f.coordinator.submit(candidate: log, for: id), .failed)
        XCTAssertEqual(f.coordinator.treatedCount, 0)
    }

    func testPrivateEditorStateAndUnrepresentableDraftStillBlock() throws {
        let f = try DayComposerStabilizationFixture(morning: [mobility], tracking: [mobility: "mobility"])
        defer { f.cleanup() }
        try f.mount(.morning)
        f.handles[0].setCount(4, identity: "unconfirmed")
        XCTAssertThrowsError(try f.barrier.withStabilizedSource(.morning) { _ in XCTFail("Private state ignored") })
        XCTAssertFalse(f.barrier.isInteractionFrozen)
        let vm = f.vms[0]
        vm.sets[0].protocolCompleted = true
        vm.sets[0].duration = 45
        XCTAssertNil(vm.buildLogCandidate(alreadyLoggedViaBinding: false))
        XCTAssertEqual(vm.sets[0].duration, 45)
        XCTAssertEqual(f.coordinator.treatedCount, 0)
    }

    func testDeliveredMobilityWithoutApplicationConfirmationCannotFinish() async throws {
        let r = try DayComposerFinishRig(names: [mobility, strength], tracking: [mobility: "mobility"])
        defer { r.cleanup() }
        r.exerciseHook = { request in
            let record = DayComposerFinishRig.record(request.operationKey)
            r.statuses[request.operationKey] = .delivered(record)
            return .transportDeliveredUnverified(record)
        }
        await r.engine.finishSource(.morning, rpe: 7)
        XCTAssertNotEqual(r.engine.productState(.morning), .completed)
        let posted = r.posted
        await r.engine.refreshSource(.morning)
        XCTAssertEqual(r.posted, posted)
        XCTAssertEqual(r.completionCalls, 0)
        XCTAssertFalse(r.engine.dayCompleted)
    }
}
