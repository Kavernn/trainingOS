import XCTest
@testable import TrainingOS

final class DayComposerPartialRestorationTests: XCTestCase {
    private func snapshot(am: [String], pm: [String]) throws -> DayComposerSnapshot {
        try DayComposerSnapshot(date: "2098-10-08", activeProgramID: "isolated-r131",
            morning: DayComposerPlan(source: .morning, session: "AM", schemes: Dictionary(uniqueKeysWithValues: am.map { ($0, "3x10") }), order: am),
            evening: DayComposerPlan(source: .evening, session: "PM", schemes: Dictionary(uniqueKeysWithValues: pm.map { ($0, "3x10") }), order: pm),
            morningCompleted: false, eveningCompleted: false)
    }

    private func restore(_ snapshot: DayComposerSnapshot, order: [DayComposerItemID]? = nil,
                         overrides: [DayComposerState.Assignment]) throws -> [DayComposerUnit] {
        let suite = "R131-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DayComposerStore(defaults: defaults)
        try store.save(snapshot.initialUnits, for: snapshot)
        let key = try XCTUnwrap(defaults.dictionaryRepresentation().keys.first { $0.hasPrefix("day_composer_order.") })
        let saved = DayComposerState(version: 2, date: snapshot.date, activeProgramID: snapshot.activeProgramID,
            sourceFingerprint: try snapshot.fingerprint, orderedItemIDs: order ?? snapshot.initialIDs, assignments: overrides)
        let bytes = try JSONEncoder().encode(saved)
        defaults.set(bytes, forKey: key)
        guard case .restored(let units) = try store.load(snapshot) else { throw DayComposerError.invalidPlan }
        XCTAssertEqual(defaults.data(forKey: key), bytes, "Read must not rewrite the user's snapshot")
        XCTAssertEqual(Set(units.flatMap(\.items).map(\.id)), Set(snapshot.initialIDs))
        return units
    }

    func testExactEightExercisePushBWithRealPMWarmupsAndThreeSparseOverrides() throws {
        let original = ["Cable Lateral Raise", "Dumbbell Lateral Raise", "Rear Delt Cable Fly", "Barbell Upright Row",
                        "Triceps Pushdown", "Single-Arm Triceps Extension", "Neck Extension", "Neck Curl"]
        let warmups = ["Wall Slides", "Thoracic Extension"]
        let s = try snapshot(am: ["Morning Press"], pm: warmups + original)
        let moved: Set<String> = ["Dumbbell Lateral Raise", "Neck Extension", "Neck Curl"]
        let overrides = s.evening.units.flatMap(\.items).filter { moved.contains($0.name) }
            .map { DayComposerState.Assignment(id: $0.id, source: .morning) }
        let effective = try s.assigning(restore(s, overrides: overrides))
        XCTAssertEqual(effective.evening.units.flatMap(\.items).map(\.name), warmups + original.filter { !moved.contains($0) })
        XCTAssertEqual(effective.morning.units.flatMap(\.items).count, 4)
    }

    func testBothDirectionsKeepEveryOccurrence() throws {
        let s = try snapshot(am: ["M1", "M2", "M3"], pm: ["E1", "E2", "E3"])
        let units = try restore(s, overrides: [.init(id: s.morning.units[1].id, source: .evening),
                                               .init(id: s.evening.units[1].id, source: .morning)])
        let effective = try s.assigning(units)
        XCTAssertEqual(Set(effective.morning.units.flatMap(\.items).map(\.name)), Set(["M1", "M3", "E2"]))
        XCTAssertEqual(Set(effective.evening.units.flatMap(\.items).map(\.name)), Set(["E1", "E3", "M2"]))
        XCTAssertEqual(units.count, 6)
    }

    func testAbsentAssignmentRetainsOriginAndPartialOrderIsNotWhitelist() throws {
        let s = try snapshot(am: ["M"], pm: ["A", "B", "C", "D", "E"])
        let units = try restore(s, order: [s.evening.units[2].id, s.evening.units[0].id],
            overrides: [.init(id: s.evening.units[1].id, source: .morning)])
        XCTAssertEqual(units.flatMap(\.items).map(\.name), ["C", "A", "M", "B", "D", "E"])
        XCTAssertEqual(units.filter { $0.source == .evening }.flatMap(\.items).map(\.name), ["C", "A", "D", "E"])
    }

    func testHomonymsWithSparseAssignmentKeepDistinctOriginIdentity() throws {
        let s = try snapshot(am: ["Curl", "M"], pm: ["Curl", "E"])
        let units = try restore(s, overrides: [.init(id: s.evening.units[0].id, source: .morning)])
        let curls = units.flatMap(\.items).filter { $0.name == "Curl" }
        XCTAssertEqual(curls.count, 2)
        XCTAssertEqual(Set(curls.map(\.id)).count, 2)
        XCTAssertTrue(curls.allSatisfy { $0.assignedSource == .morning })
        XCTAssertNotEqual(curls[0].id.occurrenceKey, curls[1].id.occurrenceKey)
    }
}
