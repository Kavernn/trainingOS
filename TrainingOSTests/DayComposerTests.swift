import XCTest
#if canImport(TrainingOS)
@testable import TrainingOS
#endif

final class DayComposerTests: XCTestCase {
    private func snapshot(date: String = "2026-09-26", program: String = "A",
                          morning: [String] = ["A", "B"], evening: [String] = ["C", "D"],
                          completed: Bool = false) throws -> DayComposerSnapshot {
        try DayComposerSnapshot(date: date, activeProgramID: program,
            morning: DayComposerPlan(source: .morning, session: "AM",
                schemes: Dictionary(uniqueKeysWithValues: morning.map { ($0, "3x10") }), order: morning),
            evening: DayComposerPlan(source: .evening, session: "PM",
                schemes: Dictionary(uniqueKeysWithValues: evening.map { ($0, "3x10") }), order: evening),
            morningCompleted: completed, eveningCompleted: false)
    }

    private func withStore(_ body: (DayComposerStore) throws -> Void) rethrows {
        let suite = "DayComposerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(DayComposerStore(defaults: defaults))
    }

    private func names(_ units: [DayComposerUnit]) -> [String] { units.flatMap { $0.items.map(\.name) } }

    func testInitialMerge() throws {
        let s = try snapshot()
        XCTAssertEqual(names(s.initialUnits), ["A", "B", "C", "D"])
        XCTAssertEqual(s.initialIDs.map(\.source), [.morning, .morning, .evening, .evening])
    }

    func testDuplicateNameIsSourceScopedEvenWithSameUUID() throws {
        let uuid = UUID().uuidString
        let a = DayComposerItemID(source: .morning, name: "Bench Press", exerciseID: uuid)
        let b = DayComposerItemID(source: .evening, name: "Bench Press", exerciseID: uuid)
        XCTAssertNotEqual(a, b)
        let s = try snapshot(morning: ["Bench Press"], evening: ["Bench Press"])
        XCTAssertEqual(s.initialIDs.count, 2)
        XCTAssertEqual(Set(s.initialIDs).count, 2)
    }

    func testIdentityFallbackIsTaggedAndExact() {
        XCTAssertNotEqual(DayComposerItemID(source: .morning, name: "A", exerciseID: nil),
                          DayComposerItemID(source: .morning, name: "a", exerciseID: nil))
        let uuid = UUID().uuidString
        XCTAssertEqual(DayComposerItemID(source: .morning, name: "A", exerciseID: uuid.lowercased()),
                       DayComposerItemID(source: .morning, name: "Renamed", exerciseID: uuid))
    }

    func testLocalReorderDoesNotMutateSource() throws {
        let s = try snapshot()
        let moved = DayComposerSnapshot.moving(s.initialUnits, from: IndexSet(integer: 2), to: 1)
        XCTAssertEqual(names(moved), ["A", "C", "B", "D"])
        XCTAssertEqual(names(s.morning.units), ["A", "B"])
        XCTAssertEqual(names(s.evening.units), ["C", "D"])
        try withStore { store in
            try store.save(moved, for: s)
            guard case .restored(let restored) = try store.load(s) else { return XCTFail("Not restored") }
            XCTAssertEqual(restored, moved)
        }
    }

    func testRestoreWithRecreatedStore() throws {
        let s = try snapshot()
        try withStore { store in
            let moved = DayComposerSnapshot.moving(s.initialUnits, from: IndexSet(integer: 2), to: 1)
            try store.save(moved, for: s)
            let recreated = DayComposerStore(defaults: store.defaults)
            guard case .restored(let restored) = try recreated.load(s) else { return XCTFail("Not restored") }
            XCTAssertEqual(restored, moved)
        }
    }

    func testDateIsolation() throws {
        try withStore { store in
            try store.save(snapshot().initialUnits, for: snapshot())
            guard case .initial = try store.load(snapshot(date: "2026-09-27")) else { return XCTFail("Cross-date order") }
        }
    }

    func testActiveProgramIsolationAndReturn() throws {
        try withStore { store in
            let s = try snapshot()
            let moved = DayComposerSnapshot.moving(s.initialUnits, from: IndexSet(integer: 2), to: 1)
            try store.save(moved, for: s)
            guard case .initial = try store.load(snapshot(program: "B")) else { return XCTFail("Cross-program order") }
            guard case .restored(let restored) = try store.load(s) else { return XCTFail("Lost A") }
            XCTAssertEqual(restored, moved)
        }
    }

    func testFingerprintMismatchPreservesSavedBytes() throws {
        try withStore { store in
            let s = try snapshot()
            try store.save(s.initialUnits.reversed(), for: s)
            let before = store.defaults.dictionaryRepresentation()
            let changed = try snapshot(morning: ["A", "B", "X"])
            guard case .incompatible = try store.load(changed) else { return XCTFail("Stale order accepted") }
            XCTAssertEqual(names(changed.initialUnits), ["A", "B", "X", "C", "D"])
            XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: store.defaults.dictionaryRepresentation()))
        }
    }

    func testResetOnlyTouchesComposer() throws {
        try withStore { store in
            store.defaults.set("keep", forKey: "session_recovery")
            let s = try snapshot()
            try store.save(s.initialUnits.reversed(), for: s)
            try store.reset(s)
            guard case .restored(let restored) = try store.load(s) else { return XCTFail("Missing reset") }
            XCTAssertEqual(restored, s.initialUnits)
            XCTAssertEqual(store.defaults.string(forKey: "session_recovery"), "keep")
        }
    }

    func testSupersetAtomicReorderAndValidation() throws {
        let morning = try DayComposerPlan(source: .morning, session: "AM",
            schemes: ["A": "3x10", "B": "3x10", "X": "3x10"], order: ["A", "X", "B"],
            pairs: [.init(group: "SS1", a: "A", b: "B", rest: 60)])
        let s = try DayComposerSnapshot(date: "2026-09-26", activeProgramID: "A", morning: morning,
            evening: snapshot().evening, morningCompleted: false, eveningCompleted: false)
        XCTAssertEqual(names(s.initialUnits), ["A", "B", "X", "C", "D"])
        let moved = DayComposerSnapshot.moving(s.initialUnits, from: IndexSet(integer: 0), to: 2)
        XCTAssertEqual(names(moved), ["X", "A", "B", "C", "D"])
        XCTAssertNotNil(s.units(for: moved.flatMap { $0.items.map(\.id) }))
        var split = s.initialIDs
        split.swapAt(1, 2)
        XCTAssertNil(s.units(for: split))
    }

    func testBrokenSupersetFailsClosed() {
        XCTAssertThrowsError(try DayComposerPlan(source: .morning, session: "AM",
            schemes: ["A": "3x10"], order: ["A"],
            pairs: [.init(group: "SS1", a: "A", b: "B", rest: nil)]))
    }

    func testAccessibleMoveMatchesDragAndBounds() throws {
        let initial = try snapshot().initialUnits
        let up = DayComposerSnapshot.moving(initial, from: IndexSet(integer: 2), to: 1)
        let down = DayComposerSnapshot.moving(initial, from: IndexSet(integer: 1), to: 3)
        XCTAssertEqual(up, down)
        XCTAssertEqual(DayComposerSnapshot.moving(initial, from: IndexSet(integer: 0), to: -1), initial)
        XCTAssertEqual(DayComposerSnapshot.moving(initial, from: IndexSet(integer: 3), to: 5), initial)
    }

    func testIrrelevantEntry() throws {
        XCTAssertFalse(try snapshot(evening: []).isRelevant(hasSavedOrder: false))
        XCTAssertFalse(try snapshot(morning: []).isRelevant(hasSavedOrder: true))
        XCTAssertFalse(try snapshot(completed: true).isRelevant(hasSavedOrder: false))
        XCTAssertTrue(try snapshot(completed: true).isRelevant(hasSavedOrder: true))
        XCTAssertTrue(try snapshot().isRelevant(hasSavedOrder: false))
        XCTAssertFalse(try snapshot(program: "").isRelevant(hasSavedOrder: false))
    }

    func testInheritedPMRequiresAssignedContent() {
        let schemes = ["A": "3x10", "B": "3x10"]
        XCTAssertTrue(DayComposerPlan.eveningSchemes(schemes, explicitlyPlanned: false, pushedToEvening: []).isEmpty)
        XCTAssertEqual(DayComposerPlan.eveningSchemes(schemes, explicitlyPlanned: false, pushedToEvening: ["B"]), ["B": "3x10"])
        XCTAssertEqual(DayComposerPlan.eveningSchemes(schemes, explicitlyPlanned: true, pushedToEvening: []), schemes)
    }

    func testReadAndEligibilityNeverPersist() throws {
        try withStore { store in
            let s = try snapshot()
            let before = store.defaults.dictionaryRepresentation()
            _ = s.isRelevant(hasSavedOrder: store.hasSavedOrder(date: s.date, program: s.activeProgramID))
            guard case .initial = try store.load(s) else { return XCTFail("Unexpected saved state") }
            XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: store.defaults.dictionaryRepresentation()))
        }
    }

    func testFingerprintDeterministicAndConfigurationSensitive() throws {
        let a = try DayComposerPlan(source: .morning, session: "AM", schemes: ["B": "3x10", "A": "3x10"], order: ["A", "B"])
        let b = try DayComposerPlan(source: .morning, session: "AM", schemes: ["A": "3x10", "B": "3x10"], order: ["A", "B"])
        let base = try snapshot()
        func fingerprint(_ plan: DayComposerPlan) throws -> String {
            try DayComposerSnapshot(date: base.date, activeProgramID: base.activeProgramID, morning: plan,
                evening: base.evening, morningCompleted: false, eveningCompleted: false).fingerprint
        }
        XCTAssertEqual(try fingerprint(a), fingerprint(b))
        let changed = try DayComposerPlan(source: .morning, session: "AM", schemes: ["A": "4x10", "B": "3x10"], order: ["A", "B"])
        XCTAssertNotEqual(try fingerprint(a), fingerprint(changed))
        XCTAssertEqual(try base.fingerprint, snapshot(completed: true).fingerprint)
    }

    func testInvalidOrderRejectedWithoutOverwriting() throws {
        try withStore { store in
            let s = try snapshot()
            XCTAssertNil(s.units(for: Array(s.initialIDs.dropFirst())))
            XCTAssertNil(s.units(for: [s.initialIDs[0], s.initialIDs[0], s.initialIDs[2], s.initialIDs[3]]))
            XCTAssertThrowsError(try store.save([s.initialUnits[0]], for: s))
            XCTAssertFalse(store.hasSavedOrder(date: s.date, program: s.activeProgramID))
        }
    }

    func testClearIsScoped() throws {
        try withStore { store in
            let a = try snapshot(), b = try snapshot(program: "B")
            try store.reset(a)
            try store.reset(b)
            store.clear(date: a.date, program: a.activeProgramID)
            XCTAssertFalse(store.hasSavedOrder(date: a.date, program: a.activeProgramID))
            XCTAssertTrue(store.hasSavedOrder(date: b.date, program: b.activeProgramID))
        }
    }

    func testUnknownVersionAndCorruptPayloadStayIncompatible() throws {
        try withStore { store in
            let s = try snapshot()
            try store.reset(s)
            let key = try XCTUnwrap(store.defaults.dictionaryRepresentation().keys.first { $0.hasPrefix("day_composer_order.") })
            let future = DayComposerState(version: 99, date: s.date, activeProgramID: s.activeProgramID,
                                          sourceFingerprint: try s.fingerprint, orderedItemIDs: s.initialIDs)
            store.defaults.set(try JSONEncoder().encode(future), forKey: key)
            guard case .incompatible = try store.load(s) else { return XCTFail("Unknown version accepted") }
            store.defaults.set(Data("broken".utf8), forKey: key)
            guard case .incompatible = try store.load(s) else { return XCTFail("Corruption accepted") }
            XCTAssertEqual(store.defaults.data(forKey: key), Data("broken".utf8))
        }
    }
}
