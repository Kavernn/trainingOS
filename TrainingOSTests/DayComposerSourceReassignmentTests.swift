import XCTest
import SwiftUI
@testable import TrainingOS

/// R13.0 contract probes, before implementation. No network or persistence writes.
/// The original red homonym contract now uses the stable occurrence key.
@MainActor
final class DayComposerSourceReassignmentTests: XCTestCase {
    private func snapshot() throws -> DayComposerSnapshot {
        let sharedID = "00000000-0000-0000-0000-000000000001"
        return try DayComposerSnapshot(date: "2026-10-05", activeProgramID: "r13-fixture",
            morning: DayComposerPlan(source: .morning, session: "AM",
                schemes: ["Commun": "1x8", "A": "1x8"], order: ["Commun", "A"],
                exerciseIDs: ["Commun": sharedID]),
            evening: DayComposerPlan(source: .evening, session: "PM",
                schemes: ["Commun": "1x8", "B": "1x8"], order: ["Commun", "B"],
                exerciseIDs: ["Commun": sharedID]),
            morningCompleted: false, eveningCompleted: false)
    }

    private func payload(_ item: DayComposerItem, source: DayComposerSource) throws -> Data {
        try WorkoutPayloadBuilder.encode(WorkoutPayloadBuilder.exercise(
            exercise: item.name, weight: 80, reps: "8", rpe: 7,
            sets: [["weight": 80, "reps": 8]], force: true,
            isSecond: source == .evening, isBonus: false,
            equipmentType: "machine", painZone: "", notes: "", date: "2026-10-05", occurrenceKey: item.id.occurrenceKey))
    }

    func testCurrentEveningItemMovedIntoMorningPositionStillBelongsToEvening() throws {
        let snapshot = try snapshot()
        let moved = DayComposerSnapshot.moving(snapshot.initialUnits, from: [2], to: 0)
        XCTAssertEqual(moved.first?.id, snapshot.evening.units.first?.id)
        XCTAssertEqual(moved.first?.source, .evening)
        XCTAssertEqual(moved.filter { $0.source == .morning }.count, 2)
    }

    func testCurrentMorningItemMovedIntoEveningPositionStillBelongsToMorning() throws {
        let snapshot = try snapshot()
        let moved = DayComposerSnapshot.moving(snapshot.initialUnits, from: [0], to: 4)
        XCTAssertEqual(moved.last?.id, snapshot.morning.units.first?.id)
        XCTAssertEqual(moved.last?.source, .morning)
        XCTAssertEqual(moved.filter { $0.source == .evening }.count, 2)
    }

    func testReorderAloneRetainsOriginRoutingBytes() throws {
        let snapshot = try snapshot()
        let moved = DayComposerSnapshot.moving(snapshot.initialUnits, from: [2], to: 0)
        let unit = try XCTUnwrap(moved.first)
        let bytes = try payload(unit.items[0], source: unit.source)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(body["is_second"] as? Bool, true)
        XCTAssertEqual(bytes, try payload(snapshot.evening.units[0].items[0], source: .evening))
    }

    func testReassignedHomonymsMustRemainDistinguishableInLogContract() throws {
        let snapshot = try snapshot()
        let morning = snapshot.morning.units[0].items[0]
        let evening = snapshot.evening.units[0].items[0]
        XCTAssertNotEqual(morning.id, evening.id)
        // Both occurrences share the effective source but retain distinct origin keys.
        XCTAssertNotEqual(try payload(morning, source: .morning),
                          try payload(evening, source: .morning),
                          "R13 blocked: distinct occurrences collapse to the same /api/log request and backend row")
    }
    func testTransfersBackCountsIdentityAndReorder() throws {
        let base = try snapshot()
        let id = base.evening.units[0].id
        let moved = try DayComposerSnapshot.transferring(base.initialUnits, id: id, locked: false)
        XCTAssertEqual(moved.flatMap(\.items).filter { $0.assignedSource == .morning }.count, 3)
        XCTAssertEqual(Set(moved.flatMap(\.items).map(\.id)), Set(base.initialIDs))
        let item = try XCTUnwrap(moved.flatMap(\.items).first { $0.id == id })
        XCTAssertEqual(item.originSource, .evening)
        XCTAssertEqual(item.assignedSource, .morning)
        XCTAssertEqual(item.occurrenceKey, id.occurrenceKey)
        let reordered = DayComposerSnapshot.moving(moved, from: [0], to: 4)
        XCTAssertEqual(reordered.last?.id, base.morning.units[0].id)
        let back = try DayComposerSnapshot.transferring(reordered, id: id, locked: false)
        XCTAssertEqual(back.flatMap(\.items).first { $0.id == id }?.assignedSource, .evening)
        let reverse = try DayComposerSnapshot.transferring(base.initialUnits, id: base.morning.units[0].id, locked: false)
        XCTAssertEqual(reverse.filter { $0.source == .evening }.count, 3)
    }

    func testSnapshotReopenResetAndInvalidation() throws {
        let suite = "R13-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DayComposerStore(defaults: defaults)
        let base = try snapshot()
        let moved = try DayComposerSnapshot.transferring(base.initialUnits, id: base.evening.units[0].id, locked: false)
        try store.save(moved, for: base)
        guard case .restored(let restored) = try store.load(base) else { return XCTFail("Missing assignments") }
        XCTAssertEqual(restored, moved)
        for value in [DayComposerSnapshot(date: "2026-10-06", activeProgramID: base.activeProgramID,
            morning: base.morning, evening: base.evening, morningCompleted: false, eveningCompleted: false),
            DayComposerSnapshot(date: base.date, activeProgramID: "new", morning: base.morning,
                evening: base.evening, morningCompleted: false, eveningCompleted: false)] {
            guard case .initial = try store.load(value) else { return XCTFail("Stale assignment reused") }
        }
        let changed = DayComposerSnapshot(date: base.date, activeProgramID: base.activeProgramID,
            morning: try .init(source: .morning, session: "Different", schemes: ["X": "1x5"], order: ["X"]),
            evening: base.evening, morningCompleted: false, eveningCompleted: false)
        guard case .incompatible = try store.load(changed) else { return XCTFail("Incompatible plan reused") }
        try store.reset(base)
        guard case .restored(let reset) = try store.load(base) else { return XCTFail() }
        XCTAssertTrue(reset.flatMap(\.items).allSatisfy { $0.originSource == $0.assignedSource })
    }

    func testLastUnitAndLockedTransfersAreRejectedWithoutMutation() throws {
        let base = try snapshot()
        let moved = try DayComposerSnapshot.transferring(base.initialUnits, id: base.evening.units[0].id, locked: false)
        XCTAssertThrowsError(try DayComposerSnapshot.transferring(moved, id: base.evening.units[1].id, locked: false))
        XCTAssertThrowsError(try DayComposerSnapshot.transferring(base.initialUnits, id: base.evening.units[0].id, locked: true))
        XCTAssertEqual(base.initialUnits[0].source, .morning)
    }

    func testSupersetAtomicAndMixedSourceRejected() throws {
        let plan = try DayComposerPlan(source: .morning, session: "AM", schemes: ["A": "1x5", "B": "1x5", "C": "1x5"],
            order: ["A", "B", "C"], pairs: [.init(group: "SS", a: "A", b: "B", rest: 90)])
        let base = try snapshot()
        let units = plan.units + base.evening.units
        let moved = try DayComposerSnapshot.transferring(units, id: plan.units[0].id, locked: false)
        let pair = try XCTUnwrap(moved.first { $0.group == "SS" })
        XCTAssertEqual(pair.items.map(\.assignedSource), [.evening, .evening])
        XCTAssertEqual(pair.items.map(\.name), ["A", "B"])
        var split = pair.items
        split[0].assignedSourceOverride = .morning
        XCTAssertThrowsError(try DayComposerSnapshot.transferring([.init(items: split, group: "SS", rest: 90)] + units.dropFirst(), id: pair.id, locked: false))
    }

    func testHomonymDraftsResultsRecoveryAndLock() throws {
        let fixture = try DayComposerStabilizationFixture(morning: ["A", "B"], evening: ["A", "B"],
            reassignment: { units in try DayComposerSnapshot.transferring(units, id: units[2].id, locked: false) })
        defer { fixture.cleanup() }
        let c = fixture.coordinator
        XCTAssertTrue(DayComposerStore.sourcesLocked(c.input.snapshot))
        try fixture.mount(.morning)
        let items = c.orderedUnits.flatMap(\.items).filter { $0.name == "A" }
        XCTAssertEqual(items.count, 2)
        for (index, item) in items.enumerated() {
            let token = try c.authorization(for: .morning)
            let draft = ExerciseDraftPersistence(date: fixture.date, sessionType: "morning", exerciseName: item.storageKey, authorization: token)
            XCTAssertTrue(draft.save([DraftSet(weight: "\(80 + index)", reps: "5", rir: 2, duration: 0)], sessionNote: "note \(index)"))
            XCTAssertEqual(draft.loadCard()?.sessionNote, "note \(index)")
        }
        for (index, item) in items.enumerated() {
            let draft = ExerciseDraftPersistence(date: fixture.date, sessionType: "morning", exerciseName: item.storageKey,
                authorization: try c.authorization(for: .morning))
            XCTAssertEqual(draft.loadCard()?.sessionNote, "note \(index)")
            var log = DayComposerFinishRig.log(item.name, source: .morning, weight: Double(80 + index))
            log.occurrenceKey = item.occurrenceKey
            XCTAssertEqual(c.submit(candidate: log, for: item.id), .accepted)
        }
        let restored = try DayComposerExecutionCoordinator.make(validatedInput: c.input, currentDate: { fixture.date })
        for (index, item) in items.enumerated() {
            XCTAssertEqual(restored.consultationResult(for: item.id)?.weight, Double(80 + index))
            XCTAssertEqual(restored.item(for: item.id)?.assignedSource, .morning)
        }
        XCTAssertEqual(restored.morningVM.logResults.count, 2)
        XCTAssertTrue(restored.eveningVM.logResults.isEmpty)
    }

    func testEffectiveFinalizationBytesHomonymsAndCoaching() async throws {
        let rig = try DayComposerFinishRig(names: ["A", "B"], reassignment: { units in
            try DayComposerSnapshot.transferring(units, id: units[2].id, locked: false)
        })
        defer { rig.cleanup() }
        let c = rig.fixture.coordinator
        XCTAssertEqual(c.setComment("AM comment", for: .morning), .accepted)
        XCTAssertTrue(rig.fixture.barrier.editComment(rig.fixture.morning, text: "AM comment"))
        let am = try rig.prepare(.morning)
        let pm = try rig.prepare(.evening)
        XCTAssertEqual(am.adapter.exercises.count, 3)
        XCTAssertEqual(pm.adapter.exercises.count, 1)
        let bodies = try am.adapter.exercises.map { try XCTUnwrap(JSONSerialization.jsonObject(with: $0.payloadData) as? [String: Any]) }
        XCTAssertEqual(Set(bodies.compactMap { $0["occurrence_key"] as? String }).count, 3)
        XCTAssertTrue(bodies.allSatisfy { ($0["is_second"] as? Bool ?? false) == false })
        let final = try XCTUnwrap(JSONSerialization.jsonObject(with: am.adapter.finalData) as? [String: Any])
        XCTAssertEqual(final["session_name"] as? String, "AM")
        XCTAssertEqual((final["exercise_logs"] as? [[String: Any]])?.count, 3)
        XCTAssertEqual(final["comment"] as? String, "AM comment")
        let restored = try DayComposerStabilizationFixture(restoring: c.input, finalInputsStore: rig.inputs)
        try restored.mount(.morning); try restored.mount(.evening)
        let engine = DayComposerFinishCoordinator(execution: restored.coordinator, barrier: restored.barrier,
            store: rig.store, inputs: rig.inputs, dependencies: .init(server: { _, source in rig.server(source) },
                status: { _ in .notFound }, exercise: { _ in .invalidResponse }, final: { _ in .invalidResponse },
                completion: { _, _ in .unconfirmed }))
        let again = try engine.prepareSource(.morning, server: rig.server(.morning))
        XCTAssertEqual(again.adapter.exercises.map(\.payloadData), am.adapter.exercises.map(\.payloadData))
        XCTAssertEqual(again.adapter.finalData, am.adapter.finalData)
        await rig.engine.finishSource(.morning, rpe: 7)
        XCTAssertEqual(rig.engine.productState(.morning), .completed)
        XCTAssertEqual(rig.engine.coaching.required[.morning]?.sessionName, "AM")
    }

    func testPreparationVisualFixtures() async throws {
        let previous = AppTheme.shared.selectedTheme
        defer { AppTheme.shared.applyTheme(previous) }
        for theme in [AppThemeOption.electricLight, .electric] {
            let scenarios: [(Bool, Bool, Bool, DynamicTypeSize)] = [
                (false, false, false, .large), (true, false, false, .large),
                (false, false, true, .large), (true, true, false, .accessibility1)]
            for (moved, locked, superset, size) in scenarios {
                AppTheme.shared.applyTheme(theme)
                let host = UIHostingController(rootView: NavigationStack {
                    try! DayComposerView.preparationFixture(moved: moved, locked: locked, superset: superset)
                }.environment(\.colorScheme, theme == .electricLight ? .light : .dark)
                    .environment(\.dynamicTypeSize, size))
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 1100))
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.setNeedsLayout(); host.view.layoutIfNeeded()
                try await Task.sleep(nanoseconds: 200_000_000)
                let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                    host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("r13-\(theme.rawValue)-\(moved)-\(locked)-\(superset).png")
                try XCTUnwrap(image.pngData()).write(to: url)
                print("R13_VISUAL \(url.path)")
                window.isHidden = true
            }
        }
    }

    func testLockDetectsClockCommentDraftAndRestoredLogsWithoutStartedFlag() throws {
        let date = try DayComposerStabilizationFixture.unusedDate()
        let original = try snapshot()
        let base = DayComposerSnapshot(date: date, activeProgramID: original.activeProgramID,
            morning: original.morning, evening: original.evening, morningCompleted: false, eveningCompleted: false)
        func clear() {
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(date) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        defer { clear() }
        XCTAssertFalse(DayComposerStore.sourcesLocked(base))
        SessionDraftStore.saveStartedAt(date: date, sessionType: "morning", startedAt: Date())
        XCTAssertTrue(DayComposerStore.sourcesLocked(base)); clear()
        SessionDraftStore.saveComment("active comment", date: date, sessionType: "evening")
        XCTAssertTrue(DayComposerStore.sourcesLocked(base)); clear()
        let draft = ExerciseDraftPersistence(date: date, sessionType: "morning", exerciseName: "fixture")
        XCTAssertTrue(draft.save([.init(weight: "80", reps: "8", rir: 2, duration: 0)]))
        XCTAssertTrue(DayComposerStore.sourcesLocked(base)); clear()
        SessionDraftStore.save(date: date, sessionType: "morning", values: [.init(name: "Commun", weight: 80,
            reps: "8", rpe: nil, isSecond: false, isBonus: false, equipmentType: "machine", painZone: "", sets: [])])
        XCTAssertTrue(DayComposerStore.sourcesLocked(base))
    }

    func testMobilityReassignmentAndPendingDoNotBlindlyResend() async throws {
        let rig = try DayComposerFinishRig(names: ["A", "B"], tracking: ["A": "mobility"], reassignment: { units in
            try DayComposerSnapshot.transferring(units, id: units[2].id, locked: false)
        })
        defer { rig.cleanup() }
        let artifact = try rig.prepare()
        let requests = artifact.adapter.exercises
        let movedKey = try XCTUnwrap(rig.fixture.coordinator.orderedUnits.flatMap(\.items)
            .first { $0.name == "A" && $0.originSource == .evening }?.occurrenceKey)
        let request = try XCTUnwrap(requests.first { $0.itemIdentity == movedKey })
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: request.payloadData) as? [String: Any])
        XCTAssertEqual(json["occurrence_key"] as? String, movedKey)
        XCTAssertNil(json["is_second"])
        XCTAssertNil(json["rpe"])
        XCTAssertEqual(json["weight"] as? Double, 0)
        rig.exerciseHook = { request in
            let receipt = DayComposerFinishRig.receipt(request.operationKey)
            rig.statuses[request.operationKey] = .pending(receipt)
            return .queued(receipt)
        }
        _ = await rig.engine.advanceSource(artifact)
        let count = rig.posted.count
        XCTAssertEqual(count, 1)
        _ = await rig.engine.advanceSource(artifact)
        XCTAssertEqual(rig.posted.count, count)
        let restored = try DayComposerStabilizationFixture(restoring: rig.fixture.coordinator.input, finalInputsStore: rig.inputs)
        try restored.mount(.morning); try restored.mount(.evening)
        var resent = false
        let engine = DayComposerFinishCoordinator(execution: restored.coordinator, barrier: restored.barrier,
            store: rig.store, inputs: rig.inputs, dependencies: .init(server: { _, source in rig.server(source) },
                status: { rig.statuses[$0] ?? .notFound },
                exercise: { _ in resent = true; return .invalidResponse },
                final: { _ in resent = true; return .invalidResponse }, completion: { _, _ in .unconfirmed }))
        let recovered = try engine.prepareSource(.morning, server: rig.server(.morning))
        XCTAssertEqual(recovered.adapter.exercises.map(\.payloadData), artifact.adapter.exercises.map(\.payloadData))
        _ = await engine.advanceSource(recovered)
        XCTAssertFalse(resent)
        XCTAssertTrue(DayComposerStore.sourcesLocked(rig.fixture.coordinator.input.snapshot))
        XCTAssertThrowsError(try DayComposerSnapshot.transferring(rig.fixture.coordinator.orderedUnits,
            id: rig.fixture.coordinator.orderedUnits[0].id, locked: true))
    }

    func testLegacyPayloadOmitsOccurrenceAndCorruptAssignmentIsNotGuessed() throws {
        let bytes = try WorkoutPayloadBuilder.encode(WorkoutPayloadBuilder.exercise(exercise: "Curl", weight: 80,
            reps: "8", rpe: nil, sets: [], force: true, isSecond: false, isBonus: false,
            equipmentType: "", painZone: "", notes: "", date: "2026-10-05"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertNil(json["occurrence_key"])
        let suite = "R13-corrupt-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DayComposerStore(defaults: defaults)
        let base = try snapshot()
        try store.save(base.initialUnits, for: base)
        let key = try XCTUnwrap(defaults.dictionaryRepresentation().keys.first { $0.hasPrefix("day_composer_order.") })
        defaults.set(Data("broken".utf8), forKey: key)
        guard case .incompatible = try store.load(base) else { return XCTFail("Corrupt assignment guessed") }
    }

    func testMixedSwapFinalSourcesRPEAndCommentsDoNotOverlap() throws {
        let rig = try DayComposerFinishRig(names: ["A", "B"], reassignment: { units in
            let moved = try DayComposerSnapshot.transferring(units, id: units[1].id, locked: false)
            return try DayComposerSnapshot.transferring(moved, id: units[2].id, locked: false)
        })
        defer { rig.cleanup() }
        XCTAssertTrue(rig.fixture.barrier.editComment(rig.fixture.morning, text: "morning"))
        XCTAssertTrue(rig.fixture.barrier.editComment(rig.fixture.evening, text: "evening"))
        try rig.fixture.coordinator.setFinalRPE(6, for: .morning)
        try rig.fixture.coordinator.setFinalRPE(9, for: .evening)
        let am = try rig.prepare(.morning).adapter
        let pm = try rig.prepare(.evening).adapter
        XCTAssertEqual(am.exercises.count, 2); XCTAssertEqual(pm.exercises.count, 2)
        XCTAssertTrue(Set(am.exercises.map(\.itemIdentity)).isDisjoint(with: Set(pm.exercises.map(\.itemIdentity))))
        for (adapter, source, name, rpe) in [(am, DayComposerSource.morning, "A", 6), (pm, .evening, "B", 9)] {
            let final = try XCTUnwrap(JSONSerialization.jsonObject(with: adapter.finalData) as? [String: Any])
            XCTAssertEqual(final["comment"] as? String, source.rawValue)
            XCTAssertEqual(final["rpe"] as? Int, rpe)
            for request in adapter.exercises {
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.payloadData) as? [String: Any])
                XCTAssertEqual(body["exercise"] as? String, name)
                XCTAssertEqual(body["is_second"] as? Bool ?? false, source == .evening)
            }
        }
    }

}
