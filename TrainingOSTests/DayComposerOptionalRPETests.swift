import XCTest
@testable import TrainingOS

/// E 5c : RPE jamais imposé dans Day Composer ; marqueur hérité 0 jamais envoyé.
@MainActor
final class DayComposerOptionalRPETests: XCTestCase {

    private func finalJSON(_ adapter: DayComposerFinalizationRequestAdapter) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: adapter.finalData) as? [String: Any])
    }

    func testTrackedWorkWithoutRPESendsNoRPEKey() throws {
        let rig = try DayComposerFinishRig(names: ["A", "B"])
        defer { rig.cleanup() }
        try rig.fixture.coordinator.setFinalRPE(nil, for: .morning)
        let adapter = try rig.prepare(.morning).adapter
        XCTAssertNil(try finalJSON(adapter)["rpe"])
    }

    func testLegacyZeroWithTrackedWorkSendsNoRPEAndSameKeyAsNil() throws {
        let rig = try DayComposerFinishRig(names: ["A", "B"])
        defer { rig.cleanup() }
        // État hérité (avant 5c) : rpe = 0 persisté. Les octets persistés ne sont pas réécrits.
        try rig.fixture.coordinator.setFinalRPE(0, for: .morning)
        let legacy = try rig.prepare(.morning).adapter
        XCTAssertNil(try finalJSON(legacy)["rpe"])          // jamais « rpe: 0 » (CHECK 1-10)
        try rig.fixture.coordinator.setFinalRPE(nil, for: .morning)
        let none = try rig.prepare(.morning).adapter
        XCTAssertEqual(legacy.finalData, none.finalData)    // mêmes octets envoyés
        XCTAssertEqual(legacy.finalKey, none.finalKey)      // même clé d'idempotence
    }

    func testChosenHalfPointIsSentExactly() throws {
        let rig = try DayComposerFinishRig(names: ["A", "B"])
        defer { rig.cleanup() }
        try rig.fixture.coordinator.setFinalRPE(7.5, for: .morning)
        XCTAssertEqual(try finalJSON(try rig.prepare(.morning).adapter)["rpe"] as? Double, 7.5)
    }

    func testPersistedRPEBytesUnchangedByOptionalType() throws {
        // Un état avec rpe garde exactement ses octets canoniques d'avant 5c.
        XCTAssertEqual(String(data: try DayComposerFinalInputs(rpe: 8).canonicalData(), encoding: .utf8),
                       "{\"contentVersion\":1,\"rpe\":8}")
    }

    func testNeutralRequestAcceptsAbsentRPEWithExercises() throws {
        let body = WorkoutPayloadBuilder.session(exos: ["A 80lbs 5"], rpe: nil, comment: "",
            durationMin: nil, energyPre: nil, secondSession: false, bonusSession: false,
            sessionName: "Pull A", exerciseLogs: [], date: "2026-11-18")
        XCTAssertNil(body["rpe"])
    }
}
