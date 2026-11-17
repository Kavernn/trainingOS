import XCTest
@testable import TrainingOS

/// E point 5 : aucun RIR / RPE inventé. Avant : SetInput.rir = 3 par défaut, envoyé avec rpe 7.
@MainActor
final class RIRNoDefaultTests: XCTestCase {

    private func machineVM(_ sets: [SetInput]) -> ExerciseViewModel {
        let vm = ExerciseViewModel(name: "Row RIR", scheme: "2x5", weightData: nil,
                                   equipmentType: "machine", isBonusSession: true,
                                   sessionDate: "rir-\(UUID().uuidString)")
        vm.sets = sets
        return vm
    }

    func testSetInputHasNoDefaultRIR() {
        XCTAssertNil(SetInput().rir)
    }

    func testUntouchedSetsSendNoRIRNorRPE() throws {
        let log = try XCTUnwrap(machineVM([SetInput(weight: "100", reps: "5"),
                                           SetInput(weight: "100", reps: "5")])
            .logExercise(alreadyLoggedViaBinding: false))
        XCTAssertEqual(log.sets.count, 2)
        for set in log.sets {
            XCTAssertNil(set["rir"])
            XCTAssertNil(set["rpe"])
        }
        XCTAssertNil(log.rpe)   // pas de RPE d'exercice inventé
    }

    func testEnteredRIROnlyOnItsSet() throws {
        let log = try XCTUnwrap(machineVM([SetInput(weight: "100", reps: "5", rir: 2),
                                           SetInput(weight: "100", reps: "5")])
            .logExercise(alreadyLoggedViaBinding: false))
        XCTAssertEqual(log.sets[0]["rir"] as? Int, 2)
        XCTAssertEqual(log.sets[0]["rpe"] as? Double, 8)
        XCTAssertNil(log.sets[1]["rir"])
        XCTAssertNil(log.sets[1]["rpe"])
        XCTAssertEqual(log.rpe, 8)   // moyenne des RIR SAISIS seulement
    }

    func testDraftSetWithoutRIRDecodesAsNil() throws {
        let json = #"{"weight":"80","reps":"5","duration":0}"#.data(using: .utf8)!
        let draft = try JSONDecoder().decode(DraftSet.self, from: json)
        XCTAssertNil(draft.rir)
        let legacy = #"{"weight":"80","reps":"5","rir":3,"duration":0}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(DraftSet.self, from: legacy).rir, 3)
    }

    private func hydrate(_ sets: [[String: Any]]) -> ExerciseRecoveryHydration? {
        let log = ExerciseLogResult(name: "Row RIR", weight: 100, reps: sets.map { $0["reps"] as! String }.joined(separator: ","),
                                    sets: sets, equipmentType: "machine")
        return ExerciseRecoveryHydration.make(log, equipment: "machine", tracking: "reps",
                                              unilateral: false, displayWeight: { $0 })
    }

    func testReconstructionToleratesMissingEffortButRejectsInvalid() throws {
        let tolerant = try XCTUnwrap(hydrate([["weight": 100.0, "reps": "5"],
                                              ["weight": 100.0, "reps": "5", "rir": 2, "rpe": 8.0]]))
        XCTAssertNil(tolerant.sets[0].rir)
        XCTAssertNil(tolerant.sets[0].rpe)
        XCTAssertEqual(tolerant.sets[1].rir, 2)
        XCTAssertEqual(tolerant.sets[1].rpe, 8)
        XCTAssertNil(hydrate([["weight": 100.0, "reps": "5", "rir": 7]]))
        XCTAssertNil(hydrate([["weight": 100.0, "reps": "5", "rpe": Double.nan]]))
        XCTAssertNil(hydrate([["weight": 100.0, "reps": "5", "rir": "deux"]]))
    }
}
