import XCTest
@testable import TrainingOS

/// E 5b : RPE de séance — aucun 7 par défaut, proposition issue des RPE réels, affichage = envoi.
final class SessionRPEProposalTests: XCTestCase {

    private func result(_ rpe: Double?) -> ExerciseLogResult {
        ExerciseLogResult(name: UUID().uuidString, weight: 100, reps: "5", rpe: rpe)
    }

    func testProposalNilWithoutRealRPE() {
        XCTAssertNil(RPEHelper.sessionProposal([ExerciseLogResult]()))
        XCTAssertNil(RPEHelper.sessionProposal([result(nil), result(nil)]))
    }

    func testProposalIsMeanOfRealRPEOnHalfPoint() {
        XCTAssertEqual(RPEHelper.sessionProposal([result(7), result(8)]), 7.5)
        XCTAssertEqual(RPEHelper.sessionProposal([result(7), result(nil), result(8)]), 7.5)   // nil ignorés
        XCTAssertEqual(RPEHelper.sessionProposal([result(9)]), 9)
    }

    func testDisplayShowsExactHalfPoint() {
        XCTAssertEqual(RPEHelper.display(7.5), "7.5")
        XCTAssertEqual(RPEHelper.display(8), "8")
        XCTAssertEqual(RPEHelper.display(10), "10")
    }

    func testSessionPayloadOmitsRPEWhenNotChosen() {
        let none = WorkoutPayloadBuilder.session(exos: ["Row 100lbs 5"], rpe: nil, comment: "",
            durationMin: 41, energyPre: nil, secondSession: false, bonusSession: false,
            sessionName: "Pull A", exerciseLogs: [], date: "2026-11-17")
        XCTAssertNil(none["rpe"])
        let chosen = WorkoutPayloadBuilder.session(exos: ["Row 100lbs 5"], rpe: 7.5, comment: "",
            durationMin: 41, energyPre: nil, secondSession: true, bonusSession: false,
            sessionName: "Pull A", exerciseLogs: [], date: "2026-11-17")
        XCTAssertEqual(chosen["rpe"] as? Double, 7.5)
    }
}
