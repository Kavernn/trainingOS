import XCTest
@testable import TrainingOS

@MainActor
final class ProgrammeViewModelTests: XCTestCase {

    func test_applyJSON_hydratesAllDicts() {
        let vm = ProgrammeViewModel()
        let json: [String: Any] = [
            "full_program": ["Push A": ["Bench": "3x8"]],
            "schedule": ["Lun": "Push A"],
            "inventory": ["Bench", "Squat"],
            "inventory_schemes": ["Bench": "3x8"],
            "inventory_muscle_groups": ["Bench": "Pectoraux"],
            "inventory_patterns": ["Bench": "Push"],
            "inventory_1rm": ["Bench": 100.0],
            "exercise_order": ["Push A": ["Bench"]],
            "session_order": ["Push A", "Legs"],
            "programs": [["id": "p1", "name": "Prog A"]],
            "current_program_id": "p1",
            "all_sessions": ["Push A", "Legs"],
        ]

        vm.applyJSON(json)

        XCTAssertEqual(vm.fullProgram["Push A"]?["Bench"], "3x8")
        XCTAssertEqual(vm.schedule["Lun"], "Push A")
        XCTAssertEqual(vm.inventory, ["Bench", "Squat"])
        XCTAssertEqual(vm.inventorySchemes["Bench"], "3x8")
        XCTAssertEqual(vm.inventoryMuscleGroups["Bench"], "Pectoraux")
        XCTAssertEqual(vm.inventoryPatterns["Bench"], "Push")
        XCTAssertEqual(vm.inventoryOneRM["Bench"], 100.0)
        XCTAssertEqual(vm.exerciseOrder["Push A"], ["Bench"])
        XCTAssertEqual(vm.apiSessionOrder, ["Push A", "Legs"])
        XCTAssertEqual(vm.programs.first?.id, "p1")
        XCTAssertEqual(vm.selectedProgramId, "p1")
        XCTAssertEqual(vm.activeProgramId, "p1")
        XCTAssertEqual(vm.allSessions, ["Push A", "Legs"])
    }

    func test_applyJSON_missingKeys_appliesDefaults() {
        let vm = ProgrammeViewModel()
        vm.applyJSON([:])

        XCTAssertTrue(vm.fullProgram.isEmpty)
        XCTAssertTrue(vm.schedule.isEmpty)
        XCTAssertTrue(vm.inventory.isEmpty)
        XCTAssertTrue(vm.programs.isEmpty)
        XCTAssertEqual(vm.selectedProgramId, "")
        XCTAssertEqual(vm.activeProgramId, "")
    }

    /// Contrat : le user peut avoir sélectionné un onglet programme avant que le
    /// serveur ne réponde. applyJSON ne doit PAS écraser ce choix, uniquement
    /// initialiser si vide. activeProgramId, lui, suit toujours le serveur.
    func test_applyJSON_preservesSelectedProgramWhenNotEmpty() {
        let vm = ProgrammeViewModel()
        vm.selectedProgramId = "user-pick"

        vm.applyJSON(["current_program_id": "p1"])

        XCTAssertEqual(vm.selectedProgramId, "user-pick")
        XCTAssertEqual(vm.activeProgramId, "p1")
    }

    func test_orderedSeances_canonicalWhenNoServerOrder() {
        let vm = ProgrammeViewModel()
        vm.fullProgram = [
            "Custom Yoga": [:],
            "Push A": [:],
            "Aardvark": [:],
            "Legs": [:],
        ]
        // apiSessionOrder vide (premier launch / jamais dragé) → fallback doctrine :
        // canonical d'abord (Push A avant Legs dans TrainingDoctrine),
        // puis les custom triées alpha (Aardvark avant Custom Yoga).
        XCTAssertEqual(vm.orderedSeances, ["Push A", "Legs", "Aardvark", "Custom Yoga"])
    }

    /// Régression commit 1 : orderedSeances ignorait apiSessionOrder, donc un drag
    /// persisté serveur était perdu à la prochaine hydratation. Fix : apiSessionOrder
    /// non-vide prime, avec filtrage des séances disparues et append des nouvelles.
    func test_orderedSeances_respectsApiSessionOrder() {
        let vm = ProgrammeViewModel()
        // Scénario : Vince a drag "Legs" en 1er, puis a ajouté "Custom Nouvelle"
        // après le dernier reorder serveur, et "Push B" a été supprimé.
        vm.fullProgram = [
            "Legs": [:],
            "Push A": [:],
            "Custom Nouvelle": [:],  // pas dans apiSessionOrder (créée après)
        ]
        vm.apiSessionOrder = ["Legs", "Push A", "Push B"]  // Push B n'existe plus

        let ordered = vm.orderedSeances

        // Base = ordre serveur, filtré des disparus (Push B out).
        // Missing = nouvelles (Custom Nouvelle) en fin, canonique+alpha.
        XCTAssertEqual(ordered, ["Legs", "Push A", "Custom Nouvelle"])
    }
}
