import XCTest
@testable import TrainingOS

/// Étape 4.3 : état « done » explicite par série, persisté (setStateVersion 1).
@MainActor
final class SetDoneStateTests: XCTestCase {
    private var date = ""
    private let exercise = "Done fixture"

    override func setUp() async throws { date = "done-\(UUID().uuidString)" }
    override func tearDown() async throws {
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(date) {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func vm(validate: (() -> LocalPersistenceResult)? = nil) -> ExerciseViewModel {
        ExerciseViewModel(name: exercise, scheme: "4x5-8", weightData: nil, sessionDate: date,
                          validateLocalPersistence: validate)
    }
    private var store: ExerciseDraftPersistence {
        ExerciseDraftPersistence(date: date, sessionType: "morning", exerciseName: exercise)
    }

    func testLegacyDraftUsesOldDerivationOnceThenBecomesVersion1() throws {
        // Ancien brouillon (aucune version) : S1, S2 remplies.
        XCTAssertTrue(store.save([DraftSet(weight: "80", reps: "5", rir: nil, duration: 0),
                                  DraftSet(weight: "80", reps: "5", rir: nil, duration: 0),
                                  DraftSet(weight: "", reps: "", rir: nil, duration: 0),
                                  DraftSet(weight: "", reps: "", rir: nil, duration: 0)]))
        XCTAssertNil(store.loadCard()?.setStateVersion)
        let a = vm(); a.initializeSets()
        XCTAssertEqual(a.currentSetIndex, 2)
        XCTAssertEqual(a.sets.map(\.done), [true, true, false, false])
        // Séance classique : la relecture réécrit déjà le brouillon (sessionNote.didSet → saveDraft,
        // comportement antérieur à 4.3, ExerciseViewModel.swift:507-513). La déduction unique est
        // donc persistée tout de suite en version 1 — valeurs inchangées, done déduits.
        let migrated = try XCTUnwrap(store.loadCard())
        XCTAssertEqual(migrated.setStateVersion, 1)
        XCTAssertEqual(migrated.sets.map { $0.done ?? false }, [true, true, false, false])
        XCTAssertEqual(migrated.sets.map(\.reps), ["5", "5", "", ""])
        // Relecture suivante : done fait foi, plus de déduction.
        let b = vm(); b.initializeSets()
        XCTAssertEqual(b.currentSetIndex, 2)
    }

    func testVersion1IndexSurvivesUndoWithFilledValues() throws {
        let a = vm(); a.initializeSets()
        a.sets[0].weight = "80"; a.sets[0].reps = "5"
        a.sets[1].weight = "80"; a.sets[1].reps = "6"
        XCTAssertEqual(a.markSet(0, done: true), .accepted)
        XCTAssertEqual(a.markSet(1, done: true), .accepted)
        XCTAssertEqual(a.markSet(1, done: false), .accepted)       // undo de S2 : valeurs gardées
        let remounted = vm(); remounted.initializeSets()
        XCTAssertEqual(remounted.currentSetIndex, 1)               // l'ancienne déduction aurait dit 2
        XCTAssertEqual(remounted.sets[1].reps, "6")
    }

    func testPendingDebounceCannotOverwriteDoneWithStaleCopy() async throws {
        let a = vm(); a.initializeSets()
        a.sets[0].weight = "80"; a.sets[0].reps = "5"             // arme le debounce (0,5 s)
        XCTAssertEqual(a.markSet(0, done: true), .accepted)        // écriture immédiate
        try await Task.sleep(nanoseconds: 900_000_000)             // le debounce se déclenche
        let saved = try XCTUnwrap(store.loadCard())
        XCTAssertEqual(saved.sets.first?.done, true)
        XCTAssertEqual(saved.sets.first?.weight, "80")
        XCTAssertEqual(saved.setStateVersion, 1)
    }

    func testImmediateRemountAfterAdvanceKeepsIndex() {
        let a = vm(); a.initializeSets()
        a.sets[0].reps = "5"
        XCTAssertEqual(a.markSet(0, done: true), .accepted)
        let b = vm(); b.initializeSets()                           // sans attendre le debounce
        XCTAssertEqual(b.currentSetIndex, 1)
    }

    func testRefusedWriteLeavesPersistedDraftByteIdentical() throws {
        var refuse = false
        let a = vm(validate: { refuse ? .rejectedContext : .accepted }); a.initializeSets()
        a.sets[0].weight = "80"; a.sets[0].reps = "5"
        XCTAssertEqual(a.markSet(0, done: true), .accepted)       // S1 validée et enregistrée
        let key = UserDefaults.standard.dictionaryRepresentation().keys.first { $0.contains(date) && $0.contains(exercise) }
        let before = try XCTUnwrap(UserDefaults.standard.data(forKey: try XCTUnwrap(key)))
        refuse = true                                              // journée invalidée
        a.sets[1].weight = "85"; a.sets[1].reps = "4"
        XCTAssertEqual(a.markSet(1, done: true), .rejectedContext)
        XCTAssertEqual(UserDefaults.standard.data(forKey: key!), before)   // octets inchangés
        let saved = try XCTUnwrap(store.loadCard())
        XCTAssertEqual(saved.sets[0].done, true)
        XCTAssertEqual(saved.sets[0].weight, "80")
    }

    func testRefusedWriteRevertsDone() {
        var refuse = false
        let a = vm(validate: { refuse ? .rejectedContext : .accepted }); a.initializeSets()
        refuse = true
        XCTAssertEqual(a.markSet(0, done: true), .rejectedContext)
        XCTAssertFalse(a.sets[0].done)
        XCTAssertEqual(a.localPersistenceIssue, .rejectedContext)
    }

    func testServerPayloadHasNoDoneKey() throws {
        let a = vm(); a.initializeSets()
        for i in a.sets.indices { a.sets[i].weight = "80"; a.sets[i].reps = "5" }
        XCTAssertEqual(a.markSet(0, done: true), .accepted)
        let log = try XCTUnwrap(a.logExercise(alreadyLoggedViaBinding: false))
        XCTAssertFalse(log.sets.contains { $0["done"] != nil })
    }
}
