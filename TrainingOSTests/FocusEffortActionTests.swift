import XCTest
@testable import TrainingOS

/// Étape 4.4a : valeurs affichées en Focus (saisie / proposée), « Série terminée », garde au log.
@MainActor
final class FocusEffortActionTests: XCTestCase {
    private var date = ""
    override func setUp() async throws { date = "effort-\(UUID().uuidString)" }
    override func tearDown() async throws {
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(date) {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func weightData(_ current: Double, lastReps: String) throws -> WeightData {
        try APIService.decoder.decode(WeightData.self, from: Data("""
            {"current_weight": \(current), "last_reps": "\(lastReps)", "last_logged": "2026-11-01", "history": []}
            """.utf8))
    }
    private func vm(_ scheme: String = "4x6-10", weight: WeightData? = nil, equipment: String = "machine",
                    prescription: ExercisePrescription? = nil) -> ExerciseViewModel {
        let v = ExerciseViewModel(name: "Effort fixture", scheme: scheme, weightData: weight, equipmentType: equipment,
                                  prescription: prescription, sessionDate: date)
        v.initializeSets()
        return v
    }

    func testRepRangeSingleSource() throws {
        XCTAssertEqual(ExerciseCalculator.repRange(scheme: "4x6-10", prescription: nil), 6...10)
        XCTAssertEqual(ExerciseCalculator.repRange(scheme: "3x10", prescription: nil), 10...10)
        XCTAssertNil(ExerciseCalculator.repRange(scheme: "3x30s", prescription: nil))
        let p = try APIService.decoder.decode(ExercisePrescription.self,
            from: Data(#"{"sets": 4, "rep_min": 8, "rep_max": 12, "note": null}"#.utf8))
        XCTAssertEqual(ExerciseCalculator.repRange(scheme: "4x6-10", prescription: p), 8...12)
    }

    /// Règle unique : même série la dernière fois, sinon BAS de la fourchette, sinon dernière valeur connue.
    func testProposedRepsRule() throws {
        let withHistory = vm(weight: try weightData(80, lastReps: "9,8,7"))
        XCTAssertEqual(withHistory.proposedReps(for: 0), 9)
        XCTAssertEqual(withHistory.proposedReps(for: 2), 7)
        XCTAssertEqual(withHistory.proposedReps(for: 3), 6)           // série en plus → bas de la fourchette
        XCTAssertEqual(vm().proposedReps(for: 0), 6)                  // aucun historique → bas, jamais le haut
        XCTAssertEqual(vm("3x30s", weight: try weightData(0, lastReps: "12")).proposedReps(for: 2), 12)
        XCTAssertNil(vm("3x30s").proposedReps(for: 0))                // rien à proposer → pas de valeur inventée
    }

    func testFillDisplayedValuesWritesShownValuesOnly() throws {
        let v = vm(weight: try weightData(80, lastReps: "9,8,7"))
        let proposedWeight = try XCTUnwrap(v.proposedWeightInput(for: 0))
        let before = try XCTUnwrap(v.fillDisplayedValues(at: 0))
        XCTAssertEqual(before.weight, ""); XCTAssertEqual(before.reps, "")
        XCTAssertEqual(v.sets[0].weight, proposedWeight)
        XCTAssertEqual(v.sets[0].reps, "9")
        v.sets[1].reps = "11"                                          // saisie : jamais écrasée
        _ = v.fillDisplayedValues(at: 1)
        XCTAssertEqual(v.sets[1].reps, "11")
    }

    func testFillRefusesWhenAValueIsMissing() {
        let v = vm()                                                   // pas de charge connue
        XCTAssertNil(v.fillDisplayedValues(at: 0))
        XCTAssertEqual(v.sets[0].weight, ""); XCTAssertEqual(v.sets[0].reps, "")
        let bodyweight = vm(equipment: "bodyweight")                   // lest facultatif
        XCTAssertNotNil(bodyweight.fillDisplayedValues(at: 0))
        XCTAssertEqual(bodyweight.sets[0].weight, "")
        XCTAssertEqual(bodyweight.sets[0].reps, "6")
    }

    /// Avancée Focus : valeurs affichées écrites puis done persisté dans le même brouillon.
    func testFilledThenMarkedDoneIsPersisted() throws {
        let v = vm(weight: try weightData(80, lastReps: "9,8,7"))
        _ = v.fillDisplayedValues(at: 0)
        XCTAssertEqual(v.markSet(0, done: true), .accepted)
        let saved = try XCTUnwrap(ExerciseDraftPersistence(date: date, sessionType: "morning",
                                                           exerciseName: "Effort fixture").loadCard())
        XCTAssertEqual(saved.sets[0].done, true)
        XCTAssertEqual(saved.sets[0].reps, "9")
        XCTAssertFalse(saved.sets[0].weight.isEmpty)
    }

    /// Garde : une série validée sans reps bloque le log (échec fort, jamais une série vide envoyée).
    func testDoneSetWithoutRepsBlocksLog() {
        let v = vm()
        v.sets[0].weight = "80"; v.sets[0].reps = "8"
        XCTAssertEqual(v.markSet(0, done: true), .accepted)
        XCTAssertEqual(v.markSet(1, done: true), .accepted)            // S2 validée vide
        XCTAssertEqual(v.logBlockedReason(), "Série 2 validée sans reps : saisis-les avant de logger")
        XCTAssertNil(v.logExercise(alreadyLoggedViaBinding: false))
        v.sets[1].weight = "80"; v.sets[1].reps = "7"
        XCTAssertNil(v.logBlockedReason())
    }

    /// 4.4b : règle unique du +/− (liste et Focus). Une valeur proposée devient saisie au 1er appui.
    func testSteppedRuleStartsFromProposedValue() {
        typealias E = ExerciseStepperEditor
        XCTAssertEqual(E.stepped("", direction: 1, increment: 5, minimum: 0, placeholder: 85, isInteger: false), "90")
        XCTAssertEqual(E.stepped("", direction: -1, increment: 5, minimum: 0, placeholder: 85, isInteger: false), "80")
        XCTAssertEqual(E.stepped("90", direction: 1, increment: 5, minimum: 0, placeholder: 85, isInteger: false), "95")
        XCTAssertEqual(E.stepped("2.5", direction: -1, increment: 5, minimum: 0, placeholder: 0, isInteger: false), "0")
        XCTAssertEqual(E.stepped("", direction: 1, increment: 2.5, minimum: 0, placeholder: 0, isInteger: false), "2.5")
        // Reps : pas de 1, minimum 1, aucun maximum.
        XCTAssertEqual(E.stepped("", direction: 1, increment: 1, minimum: 1, placeholder: 10, isInteger: true), "11")
        XCTAssertEqual(E.stepped("1", direction: -1, increment: 1, minimum: 1, placeholder: 10, isInteger: true), "1")
        XCTAssertEqual(E.stepped("", direction: -1, increment: 1, minimum: 1, placeholder: 0, isInteger: true), "1")
        XCTAssertEqual(E.stepped("99", direction: 1, increment: 1, minimum: 1, placeholder: 10, isInteger: true), "100")
    }

    /// Affiché = enregistré : jusqu'à 2 décimales, sans zéro inutile, saisie normalisée sans perte.
    func testDecimalFormattingKeepsRecordedValue() {
        let E = ExerciseStepperEditor.self
        XCTAssertEqual(E.formatted(61.25, isInteger: false), "61.25")
        XCTAssertEqual(E.formatted(60, isInteger: false), "60")
        XCTAssertEqual(E.formatted(62.5, isInteger: false), "62.5")
        XCTAssertEqual(E.normalized("61,25", minimum: 0, isInteger: false), "61.25")
        XCTAssertEqual(E.stepped("60", direction: 1, increment: 1.25, minimum: 0, placeholder: 0, isInteger: false), "61.25")
        // Aller-retour kg → lbs (stockage) → kg : le bruit de conversion ne s'affiche pas.
        XCTAssertEqual(UnitSettings.decimalString((61.25 / 0.453592) * 0.453592), "61.25")
    }
}
