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
            // session_order encore envoyé par le backend mais ignoré depuis D5
            // (orderedSeances dérive du schedule, pas de miroir apiSessionOrder).
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

    // MARK: - Doctrine dérivée : orderedSeances (D5, planning = source unique)

    /// Contrat D5 : les séances s'ordonnent selon l'apparition dans schedule
    /// (Lun → Dim). Deux occurrences de la même séance = ancrée au 1er jour.
    func test_orderedSeances_derivesFromSchedule() {
        let vm = ProgrammeViewModel()
        vm.fullProgram = ["Push A": [:], "Pull B": [:], "Legs": [:]]
        vm.schedule = ["Lun": "Push A", "Mar": "Legs", "Jeu": "Push A", "Sam": "Pull B"]
        // Push A ancré Lun (1re occurrence), Legs Mar, Pull B Sam.
        XCTAssertEqual(vm.orderedSeances, ["Push A", "Legs", "Pull B"])
    }

    /// Les séances non planifiées sont ajoutées après, triées alpha —
    /// ordre déterministe sans donner l'illusion d'un choix implicite.
    func test_orderedSeances_appendsUnscheduledAlpha() {
        let vm = ProgrammeViewModel()
        vm.fullProgram = ["Push A": [:], "Custom Yoga": [:], "Legs": [:]]
        vm.schedule = ["Lun": "Push A"]
        XCTAssertEqual(vm.orderedSeances, ["Push A", "Custom Yoga", "Legs"])
    }

    /// Robustesse : Repos et références à des séances absentes de fullProgram
    /// (schedule qui pointe une séance supprimée) sont ignorées, pas d'erreur.
    func test_orderedSeances_ignoresReposAndMissingSessions() {
        let vm = ProgrammeViewModel()
        vm.fullProgram = ["Push A": [:]]
        vm.schedule = ["Lun": "Repos", "Mar": "Push A", "Mer": "Legs"]  // Legs absent
        XCTAssertEqual(vm.orderedSeances, ["Push A"])
    }

    /// Fallback sans schedule : tri alpha pur, aucun choix canonique injecté.
    /// C'est le nouveau contrat vs Lot 2 (canonique + custom alpha) —
    /// sans planning il n'y a plus de source pour privilégier "Push A avant Legs".
    func test_orderedSeances_noScheduleFallsBackToAlpha() {
        let vm = ProgrammeViewModel()
        vm.fullProgram = ["Push A": [:], "Aardvark": [:], "Legs": [:]]
        XCTAssertEqual(vm.orderedSeances, ["Aardvark", "Legs", "Push A"])
    }

    /// Réactivité : createSeance ajoute une clé à fullProgram — sans schedule,
    /// elle apparaît en fin (alpha) sans casser l'existant.
    func test_orderedSeances_reactsToFullProgramMutation() {
        let vm = ProgrammeViewModel()
        vm.fullProgram = ["Push A": [:], "Legs": [:]]
        vm.schedule = ["Lun": "Push A", "Mar": "Legs"]
        XCTAssertEqual(vm.orderedSeances, ["Push A", "Legs"])

        vm.fullProgram["Zzz Test"] = [:]
        XCTAssertEqual(vm.orderedSeances, ["Push A", "Legs", "Zzz Test"])
    }

    /// Ordre chronologique complet : AM avant PM à l'intérieur d'un jour,
    /// jours dans l'ordre Lun→Dim. Locked In 2027 shape (double séance).
    /// Sans ça, les PM tombaient dans "unscheduled" et sortaient alpha en fin.
    func test_orderedSeances_interleavesMorningEvening() {
        let vm = ProgrammeViewModel()
        vm.fullProgram = [
            "Lundi AM — Jambes": [:], "Lundi PM — Haut": [:],
            "Mardi AM — Épaules": [:], "Mardi PM — Puissance": [:],
        ]
        vm.schedule = ["Lun": "Lundi AM — Jambes", "Mar": "Mardi AM — Épaules"]
        vm.eveningSchedule = ["Lun": "Lundi PM — Haut", "Mar": "Mardi PM — Puissance"]
        XCTAssertEqual(vm.orderedSeances, [
            "Lundi AM — Jambes", "Lundi PM — Haut",
            "Mardi AM — Épaules", "Mardi PM — Puissance",
        ])
    }

    // MARK: - Doctrine dérivée : weeklyVolumeByMuscle

    /// Verrouille le fix Lot 1 (58dab26/97ce9cb) : la valeur DB "glutes" (anglais
    /// dans une colonne française) doit mapper au groupe doctrinal "Fessiers".
    /// Test avec les valeurs DB réelles (Épaules, Dos, glutes, Ischio-jambiers…).
    func test_weeklyVolumeByMuscle_mapsDBGroupsToDoctrinal() {
        let vm = ProgrammeViewModel()
        vm.schedule = ["Lun": "Push A", "Mar": "Pull A", "Mer": "Legs"]
        vm.fullProgram = [
            "Push A": ["Bench": "3x8", "OHP": "3x8"],
            "Pull A": ["Row": "3x8", "Curl": "3x10"],
            "Legs":   ["Squat": "3x8", "HipThrust": "3x8"],
        ]
        vm.inventoryMuscleGroups = [
            "Bench":     "Pectoraux",
            "OHP":       "Épaules",
            "Row":       "Dos",
            "Curl":      "Biceps",
            "Squat":     "Quadriceps",
            "HipThrust": "glutes",  // anomalie DB (anglais) — mappée doctrinalement
        ]

        let vol = vm.weeklyVolumeByMuscle

        XCTAssertEqual(vol["Pectoraux"], 3)
        XCTAssertEqual(vol["Épaules"], 3)
        XCTAssertEqual(vol["Dos"], 3)
        XCTAssertEqual(vol["Biceps"], 3)
        XCTAssertEqual(vol["Quadriceps"], 3)
        XCTAssertEqual(vol["Fessiers"], 3, "DB 'glutes' doit mapper à Fessiers (fix Lot 1)")
    }

    /// Fréquence hebdo multiplie les sets : Push A programmé 2 jours → volume ×2.
    func test_weeklyVolumeByMuscle_countsFrequencyPerWeek() {
        let vm = ProgrammeViewModel()
        vm.schedule = ["Lun": "Push A", "Jeu": "Push A"]  // 2× / semaine
        vm.fullProgram = ["Push A": ["Bench": "4x8"]]
        vm.inventoryMuscleGroups = ["Bench": "Pectoraux"]

        let vol = vm.weeklyVolumeByMuscle

        XCTAssertEqual(vol["Pectoraux"], 8, "4 sets × 2 séances = 8 sets/sem")
    }

    /// Muscle DB inconnu (jamais rencontré, ex: "Cou" non mappé) = skip silencieux.
    /// Robustesse contre l'ajout futur de valeurs DB non encore doctrinales.
    func test_weeklyVolumeByMuscle_skipsUnmappedMuscles() {
        let vm = ProgrammeViewModel()
        vm.schedule = ["Lun": "Push A"]
        vm.fullProgram = ["Push A": ["Bench": "3x8", "Shrug": "3x10"]]
        vm.inventoryMuscleGroups = [
            "Bench": "Pectoraux",
            "Shrug": "MuscleInexistant",  // pas dans doctrinalMuscleGroup
        ]

        let vol = vm.weeklyVolumeByMuscle

        XCTAssertEqual(vol["Pectoraux"], 3)
        XCTAssertNil(vol["MuscleInexistant"])
        XCTAssertEqual(vol.count, 1, "Seul le muscle mappé apparaît, l'autre est silencieusement ignoré")
    }

    // MARK: - Doctrine dérivée : volumeAlerts

    /// Pectoraux 8 sets < MEV 10 → doit être flaggé. Format alerte préservé.
    func test_volumeAlerts_flagsUnderMEV() {
        let vm = ProgrammeViewModel()
        vm.schedule = ["Lun": "Push A", "Jeu": "Push A"]  // 2×
        vm.fullProgram = ["Push A": ["Bench": "4x8"]]     // 4 sets × 2 = 8
        vm.inventoryMuscleGroups = ["Bench": "Pectoraux"]

        let alerts = vm.volumeAlerts

        XCTAssertEqual(alerts, ["Pectoraux — 8/10 sets min."])
    }

    /// Un muscle absent (0 sets) ne doit PAS générer une alerte "0/X sets" —
    /// weeklyVolumeByMuscle ne l'inclut même pas dans son dict retourné.
    func test_volumeAlerts_ignoresZeroSets() {
        let vm = ProgrammeViewModel()
        vm.schedule = ["Lun": "Push A"]
        vm.fullProgram = ["Push A": ["Bench": "3x8"]]  // uniquement Pectoraux
        vm.inventoryMuscleGroups = ["Bench": "Pectoraux"]

        let alerts = vm.volumeAlerts

        // Pectoraux 3 sets < MEV 10 → 1 alerte. Les autres muscles (Dos, Biceps…)
        // ne doivent PAS apparaître comme "0/X".
        XCTAssertEqual(alerts, ["Pectoraux — 3/10 sets min."])
    }
}
