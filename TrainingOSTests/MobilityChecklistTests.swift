import XCTest
@testable import TrainingOS

@MainActor
final class MobilityChecklistTests: XCTestCase {
    private final class EveningProbe: SeanceSoirViewModel {
        var healthKitCalls = 0
        override func sendEveningSession(exos: [String], rpe: Double, comment: String,
            durationMin: Double?, energyPre: Int?, sessionName: String?,
            exerciseLogs: [[String: Any]]) async throws -> SessionSaveOutcome {
            XCTAssertTrue(exos.isEmpty); XCTAssertTrue(exerciseLogs.isEmpty)
            return .serverResponse(.init(success: true))
        }
        override func refreshEveningDashboard() async {}
        override func observeEveningCompletion(date: String) async -> Bool { true }
        override func recordEveningWorkout() async { healthKitCalls += 1 }
    }
    private final class BonusProbe: BonusSeanceViewModel {
        var healthKitCalls = 0
        override func sendBonusSession(exos: [String], rpe: Double, comment: String,
            durationMin: Double?, energyPre: Int?, exerciseLogs: [[String: Any]]) async throws -> SessionSaveOutcome {
            XCTAssertTrue(exos.isEmpty); XCTAssertTrue(exerciseLogs.isEmpty)
            return .serverResponse(.init(success: true))
        }
        override func refreshBonusDashboard() async {}
        override func recordBonusWorkout() async { healthKitCalls += 1 }
    }

    func testClassicMobilityOnlyFinishesWithoutCallingHealthKit() async throws {
        let date = "mobility-finish-\(UUID().uuidString)"
        let evening = EveningProbe(), bonus = BonusProbe()
        for owner in [evening as SeanceViewModel, bonus] {
            owner.seanceData = try APIService.decoder.decode(SeanceData.self,
                from: Fixtures.seanceDataJSON(todayDate: date, alreadyLogged: false))
            defer {
                _ = owner.chrono.stop()
                SessionDraftStore.clear(date: date, sessionType: owner.draftSessionType)
            }
            await owner.finish(rpe: 7, comment: "Checklist")
            XCTAssertTrue(owner.showSuccess)
            XCTAssertNil(owner.submitError)
        }
        XCTAssertEqual(evening.healthKitCalls, 0)
        XCTAssertEqual(bonus.healthKitCalls, 0)
        let neutral = WorkoutPayloadBuilder.session(exos: [], rpe: 7, comment: "Checklist",
            durationMin: 10, energyPre: nil, secondSession: false, bonusSession: false,
            sessionName: "Mobilité", exerciseLogs: [], date: date)
        XCTAssertNil(neutral["rpe"])
        XCTAssertEqual(neutral["comment"] as? String, "Checklist")
    }

    func testExactMixedSessionUncheckedMobilityNeverMissing() async throws {
        let r = try DayComposerFinishRig(names: ["A", "B", "M1", "M2"], tracking: ["M1": "mobility", "M2": "mobility"])
        defer { r.cleanup() }
        let c = r.fixture.coordinator
        let id = try XCTUnwrap(c.input.snapshot.morning.units.flatMap(\.items).first { $0.name == "M2" }?.id)
        try c.setResult(nil, for: id)
        XCTAssertNotNil(c.morningVM.logResults["M1"])
        XCTAssertNil(c.morningVM.logResults["M2"])
        // Both sources are identical; only AM's unchecked checklist differs.
        XCTAssertEqual(c.executableCount, 4)
        XCTAssertEqual(c.treatedCount, 4)
        XCTAssertTrue(c.canOfferFinish(.morning), "Unchecked mobility must not disable the finish button")
        await r.engine.finishSource(.morning, rpe: 7)
        XCTAssertEqual(r.engine.productState(.morning), .completed, String(describing: r.engine.productResults[.morning]))
    }
    func testClassicCountsMissingAndHealthKitAcrossAllOwners() {
        let tracking = ["M1": "mobility", "M2": "mobility"]
        let names = ["A", "B", "M1", "M2"]
        for owner in [SeanceViewModel(draftSessionType: "morning"), SeanceSoirViewModel(), BonusSeanceViewModel()] {
            XCTAssertFalse(owner.hasPerformedTrackedWork, "Planned or skipped exercises are not logged evidence")
            var marker = DayComposerFinishRig.log("M1", source: .morning)
            marker.trackingType = "mobility"; marker.rpe = nil
            owner.logResults = ["M1": marker]
            XCTAssertFalse(owner.hasPerformedTrackedWork)
            XCTAssertEqual(WorkoutCompletion.trackedNames(names, tracking: tracking), ["A", "B"])
            owner.logResults["A"] = DayComposerFinishRig.log("A", source: .morning)
            XCTAssertTrue(owner.hasPerformedTrackedWork)
            XCTAssertEqual(WorkoutCompletion.missing(names, results: owner.logResults, tracking: tracking), ["B"])
            owner.logResults["B"] = DayComposerFinishRig.log("B", source: .morning)
            XCTAssertEqual(WorkoutCompletion.performed(owner.logResults).count, 2)
            XCTAssertTrue(WorkoutCompletion.missing(names, results: owner.logResults, tracking: tracking).isEmpty)
            XCTAssertEqual(WorkoutPayloadBuilder.summaries(owner.logResults).exerciseLogs.count, 2)
        }
    }

    func testClassicChecklistPersistsWithoutSetsOrPerformanceAndKeepsSourceDate() {
        let date = "mobility-checklist-\(UUID().uuidString)"
        for source in ["morning", "evening", "bonus"] {
            let store = ExerciseDraftPersistence(date: date, sessionType: source, exerciseName: "M1")
            defer { _ = store.clear() }
            XCTAssertTrue(store.saveMobilityChecked(true))
            // A new persistence owner is the same path used after view/background re-entry.
            let reopened = ExerciseDraftPersistence(date: date, sessionType: source, exerciseName: "M1")
            XCTAssertEqual(reopened.loadCard()?.mobilityChecked, true)
            XCTAssertEqual(reopened.loadCard()?.sets.count, 0)
            XCTAssertEqual(reopened.saveResult([], sessionNote: "Guidance"), .accepted)
            XCTAssertEqual(store.loadCard()?.mobilityChecked, true, "Ordinary draft saves preserve the checkbox")
            XCTAssertNil(ExerciseDraftPersistence(date: date + "next", sessionType: source, exerciseName: "M1").loadCard())
            XCTAssertNil(ExerciseDraftPersistence(date: date, sessionType: source, exerciseName: "M2").loadCard())
            XCTAssertTrue(SessionDraftStore.load(date: date, sessionType: source).isEmpty)
            XCTAssertTrue(reopened.saveMobilityChecked(false))
            XCTAssertEqual(store.loadCard()?.mobilityChecked, false)
        }
    }

    func testMobilityOnlyClosesBothSourcesWithoutPerformanceSummaryRPEOrCoaching() async throws {
        for checked in [false, true] {
            let r = try DayComposerFinishRig(names: ["M1", "M2"], tracking: ["M1": "mobility", "M2": "mobility"])
            defer { r.cleanup() }
            if !checked {
                // Model leaving and re-entering the cards: retire the existing
                // participants before mounting fresh unchecked editors.
                let ids = [DayComposerSource.morning, .evening].flatMap {
                    r.fixture.coordinator.expectedMutableParticipantIDs(for: $0)
                }
                for (id, handle) in zip(ids, r.fixture.handles) {
                    r.fixture.barrier.unregister(identity: id, token: handle.instance)
                    handle.detach()
                }
                r.fixture.handles.removeAll(); r.fixture.vms.removeAll()
                for id in r.fixture.coordinator.input.snapshot.initialIDs { try r.fixture.coordinator.setResult(nil, for: id) }
                try r.fixture.mount(.morning)
                try r.fixture.mount(.evening)
                for vm in r.fixture.vms { _ = vm.flushPendingLocalPersistence() }
            }
            XCTAssertEqual(r.fixture.coordinator.executableCount, 0)
            XCTAssertEqual(r.fixture.coordinator.treatedCount, 0)
            XCTAssertTrue(r.fixture.coordinator.canOfferFinish(.morning))
            XCTAssertTrue(r.fixture.coordinator.canOfferFinish(.evening))
            r.finalHook = { request in
                guard let json = (try? JSONSerialization.jsonObject(with: request.payloadData)) as? [String: Any] else {
                    XCTFail("Invalid final payload"); return .invalidResponse
                }
                XCTAssertEqual(json["exos"] as? [String], [])
                XCTAssertNil(json["exercise_logs"])
                XCTAssertNil(json["rpe"])
                r.statuses[request.operationKey] = .delivered(DayComposerFinishRig.record(request.operationKey))
                return .applicationConfirmed(.init(success: true))
            }
            await r.engine.finishSource(.morning, rpe: 7)
            await r.engine.finishSource(.evening, rpe: 7)
            XCTAssertEqual(r.engine.productState(.morning), .completed, String(describing: r.engine.productResults[.morning]))
            XCTAssertEqual(r.engine.productState(.evening), .completed)
            XCTAssertTrue(r.engine.coaching.required.isEmpty)
            XCTAssertTrue(r.engine.dayCompleted)
        }
    }

}
