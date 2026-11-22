import XCTest
import SwiftUI
import UIKit
@testable import TrainingOS

/// 4.4a/c bout en bout dans la vraie WorkoutSeanceView : « Série terminée » activé via l'accessibilité
/// (même chemin que VoiceOver), dernière série → Transition épinglée, sortie manuelle.
@MainActor
final class FocusFlowTests: XCTestCase {
    private var date = ""
    private var exercise = ""
    private var flagBefore: Any?
    private var window: UIWindow!
    private var host: UIViewController!

    override func setUp() async throws {
        date = "focus-flow-\(UUID().uuidString)"
        exercise = "Row-\(UUID().uuidString.prefix(6))"
        flagBefore = UserDefaults.standard.object(forKey: FocusModePreference.key)
        UserDefaults.standard.set(true, forKey: FocusModePreference.key)
    }
    override func tearDown() async throws {
        window?.isHidden = true; window?.rootViewController = nil; window = nil; host = nil
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(date) {
            UserDefaults.standard.removeObject(forKey: key)
        }
        if let flagBefore { UserDefaults.standard.set(flagBefore, forKey: FocusModePreference.key) }
        else { UserDefaults.standard.removeObject(forKey: FocusModePreference.key) }
    }

    private func settle(_ rounds: Int = 4) async throws {
        for _ in 0..<rounds { host.view.layoutIfNeeded(); try await Task.sleep(nanoseconds: 150_000_000) }
    }

    private func primaryAction() { NotificationCenter.default.post(name: FocusSwitch.debugFocusPrimaryAction, object: nil) }
    /// Carte affichée (instance non retirée) pour un exercice.
    private func active(_ name: String) -> ExerciseViewModel? {
        ExerciseViewModel.debugLive.first { $0.name == name && $0.sessionDate == date && !$0.isRetired }
    }

    private func mount(owner: SeanceViewModel, data: SeanceData) async throws {
        let root = TabView {
            NavigationStack { WorkoutSeanceView(data: data, vm: owner, isOverride: true) }
                .tabItem { Label("Séance", systemImage: "dumbbell.fill") }
        }
        host = UIHostingController(rootView: root)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host; window.makeKeyAndVisible()
        try await settle(6)
    }

    func testCompleteSetsThenTransitionPinnedUntilManualContinue() async throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Fixtures.seanceDataJSON(
            today: "Pull B", todayDate: date, exerciseName: exercise,
            historyDate: "2026-11-15", historyWeight: 85, historyReps: "10,9")) as? [String: Any])
        json["full_program"] = ["Pull B": [exercise: "2x8-10", "Shrug": "3x10"]]
        let data = try APIService.decoder.decode(SeanceData.self, from: JSONSerialization.data(withJSONObject: json))
        let owner = SeanceViewModel(draftSessionType: "morning", followsActivePlanning: true)
        owner.seanceData = data
        owner.startSession()
        owner.currentPlanningLoader = { _, _ in ("stale", data) }
        try await mount(owner: owner, data: data)

        let store = ExerciseDraftPersistence(date: date, sessionType: "morning", exerciseName: exercise)
        XCTAssertNotNil(active(exercise))
        primaryAction()                                              // « Série terminée » S1
        try await settle()
        let afterS1 = try XCTUnwrap(store.loadCard())
        XCTAssertEqual(afterS1.sets[0].done, true)
        XCTAssertEqual(afterS1.sets[0].reps, "10")                  // valeur affichée (proposée) enregistrée
        XCTAssertFalse(afterS1.sets[0].weight.isEmpty)
        XCTAssertEqual(active(exercise)?.currentSetIndex, 1)

        try await Task.sleep(nanoseconds: 900_000_000)              // anti-rebond 0,8 s
        primaryAction()                                              // S2 = dernière → doLog
        try await settle(6)
        XCTAssertNotNil(owner.logResults[exercise])
        XCTAssertEqual(owner.logResults[exercise]?.reps.split(separator: ",").count, 2)
        // Transition épinglée : la carte loggée reste affichée, Shrug pas encore monté.
        try await Task.sleep(nanoseconds: 1_000_000_000)
        try await settle()
        XCTAssertNotNil(active(exercise), "Transition : la carte loggée reste affichée")
        XCTAssertNil(active("Shrug"), "pas de passage automatique")
        primaryAction()                                              // « Suivant : Shrug »
        try await settle(6)
        XCTAssertNotNil(active("Shrug"), "sortie manuelle vers Shrug")
        XCTAssertNil(active(exercise))
    }

    // MARK: - 4.4d : superset A ↔ B

    private var restTimer: RestTimerManager { RestTimerManager.shared }

    /// Paire Bench (A) / Dips (B), repos 90 s ; les deux avec un historique (valeurs proposées).
    private func mountPair(schemeA: String, schemeB: String, otherLogged: Bool = false) async throws -> SeanceViewModel {
        let restPrefBefore = UserDefaults.standard.object(forKey: AutoRestPreference.key) as? Bool
        UserDefaults.standard.set(true, forKey: AutoRestPreference.key)
        addTeardownBlock {
            await MainActor.run {
                RestTimerManager.shared.dismiss()
                if let restPrefBefore { UserDefaults.standard.set(restPrefBefore, forKey: AutoRestPreference.key) }
                else { UserDefaults.standard.removeObject(forKey: AutoRestPreference.key) }
            }
        }
        restTimer.dismiss()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Fixtures.seanceDataJSON(
            today: "Push", todayDate: date, exerciseName: "Bench",
            historyDate: "2026-11-15", historyWeight: 135, historyReps: "8,8,8")) as? [String: Any])
        json["full_program"] = ["Push": ["Bench": schemeA, "Dips": schemeB, "Fly": "3x12"]]
        json["exercise_order"] = ["Push": ["Bench", "Dips", "Fly"]]
        json["exercise_supersets"] = ["Push": ["Bench": ["A": "Bench", "B": "Dips", "rest": 90]]]
        var weights = try XCTUnwrap(json["weights"] as? [String: Any])
        weights["Dips"] = ["current_weight": 25, "last_reps": "10,10,10,10", "last_logged": "2026-11-15",
                           "history": [["date": "2026-11-15", "weight": 25, "reps": "10,10,10,10"]]]
        json["weights"] = weights
        let data = try APIService.decoder.decode(SeanceData.self, from: JSONSerialization.data(withJSONObject: json))
        let owner = SeanceViewModel(draftSessionType: "morning", followsActivePlanning: true)
        owner.seanceData = data
        owner.startSession()
        // Défaut préexistant (ExerciseViewModel.persistDraftIfNeeded) : annuler le SEUL log de la séance
        // remet sessionStarted à false → Focus repasse en liste. Un autre exercice loggé isole le cas paire.
        if otherLogged { owner.logResults["Fly"] = ExerciseLogResult(name: "Fly", weight: 30, reps: "12,12,12") }
        owner.currentPlanningLoader = { _, _ in ("stale", data) }
        try await mount(owner: owner, data: data)
        return owner
    }

    /// Action principale puis attente (anti-rebond 0,8 s + bascule par la porte).
    private func step() async throws {
        primaryAction()
        try await Task.sleep(nanoseconds: 900_000_000)
        try await settle()
    }
    private func pairUndo() async throws {
        NotificationCenter.default.post(name: FocusSwitch.debugFocusPairUndo, object: nil)
        try await settle(6)
    }
    private func liveNames() -> [String] {
        ExerciseViewModel.debugLive.filter { $0.sessionDate == date && !$0.isRetired }.map(\.name).sorted()
    }
    private func card(_ name: String) -> ExerciseDraftPersistence {
        ExerciseDraftPersistence(date: date, sessionType: "morning", exerciseName: name)
    }

    /// Paire 3/4 de bout en bout : alternance, repos de B seulement, A fini → B seul, Transition à la fin.
    func testSupersetThreeFourAlternatesThenTransitionAtPairEnd() async throws {
        let owner = try await mountPair(schemeA: "3x8-10", schemeB: "4x8-10")
        XCTAssertNotNil(active("Bench"))
        for round in 1...3 {
            try await step()                                          // A S\(round)
            XCTAssertNotNil(active("Dips"), "A S\(round) → B")
            XCTAssertNil(active("Bench"))
            if round < 3 {
                XCTAssertEqual(card("Bench").loadCard()?.sets[round - 1].done, true)
            } else {
                XCTAssertNotNil(owner.logResults["Bench"], "A S3 = dernière → A loggé")
            }
            XCTAssertEqual(active("Dips")?.currentSetIndex, round - 1)
            if round == 1 { XCTAssertFalse(restTimer.isVisible, "A ne lance pas de repos") }
            try await step()                                          // B S\(round)
            XCTAssertTrue(restTimer.isVisible, "repos de B après B S\(round)")
            if round < 3 {
                XCTAssertNotNil(active("Bench"), "B S\(round) → A, repos de B toujours affiché")
                XCTAssertEqual(active("Bench")?.currentSetIndex, round)
            }
        }
        // A est fini : B S3 reste sur B (repos de B), puis B S4 = fin réelle de la paire.
        XCTAssertNotNil(active("Dips"), "A fini → on reste sur B")
        XCTAssertEqual(active("Dips")?.currentSetIndex, 3)
        let runBeforeEnd = restTimer.runID
        try await step()                                              // B S4 → doLog
        try await Task.sleep(nanoseconds: 1_000_000_000)
        try await settle()
        XCTAssertNotNil(owner.logResults["Dips"])
        XCTAssertEqual(owner.logResults["Dips"]?.reps.split(separator: ",").count, 4)
        XCTAssertEqual(owner.logResults["Bench"]?.reps.split(separator: ",").count, 3)
        XCTAssertEqual(restTimer.runID, runBeforeEnd, "fin réelle de la paire : pas de nouveau repos (Build G)")
        XCTAssertNotNil(active("Dips"), "Transition épinglée sur le dernier membre")
    }

    /// Undo croisé (série) : A S1 → sur B, undo → retour sur A, S1 à refaire ; B S1 → sur A, undo → B, repos arrêté.
    func testSupersetCrossUndoOfSet() async throws {
        _ = try await mountPair(schemeA: "3x8-10", schemeB: "3x8-10")
        try await step()                                              // A S1 → B
        XCTAssertNotNil(active("Dips"))
        try await pairUndo()
        XCTAssertNotNil(active("Bench"), "undo croisé → retour sur A")
        XCTAssertEqual(active("Bench")?.currentSetIndex, 0)
        XCTAssertNil(try XCTUnwrap(card("Bench").loadCard()).sets[0].done, "S1 non faite (done encodé seulement si true)")

        try await step()                                              // A S1 → B
        try await step()                                              // B S1 → A, repos de B
        XCTAssertNotNil(active("Bench"))
        XCTAssertTrue(restTimer.isVisible)
        try await pairUndo()
        XCTAssertNotNil(active("Dips"), "undo croisé → retour sur B")
        XCTAssertEqual(active("Dips")?.currentSetIndex, 0)
        XCTAssertNil(try XCTUnwrap(card("Dips").loadCard()).sets[0].done, "S1 non faite (done encodé seulement si true)")
        XCTAssertFalse(restTimer.isVisible, "le repos lancé par la série annulée s'arrête")
    }

    /// Undo croisé (log) + exception de repos : B finit avant A → log de B + repos de la paire ;
    /// undo depuis A → B dé-loggé, séries restaurées, dernière série à refaire, repos arrêté.
    func testSupersetCrossUndoOfLogAndPairRestException() async throws {
        let owner = try await mountPair(schemeA: "2x8-10", schemeB: "1x8-10", otherLogged: true)
        try await step()                                              // A S1 → B
        try await step()                                              // B S1 = dernière → log + repos
        XCTAssertNotNil(owner.logResults["Dips"])
        XCTAssertTrue(restTimer.isVisible, "exception : log de B avant la fin de la paire → repos entre deux tours")
        XCTAssertNotNil(active("Bench"), "pas de Transition : A a encore une série")
        XCTAssertEqual(active("Bench")?.currentSetIndex, 1)

        try await pairUndo()
        XCTAssertNil(owner.logResults["Dips"], "undo croisé du log")
        XCTAssertFalse(restTimer.isVisible, "repos du log arrêté")
        XCTAssertEqual(liveNames(), ["Dips"], "Focus : une seule carte, B")
        let dips = try XCTUnwrap(active("Dips"), "retour sur B")
        XCTAssertEqual(dips.currentSetIndex, 0)
        XCTAssertEqual(dips.sets.first?.reps, "10", "séries du log restaurées")
        XCTAssertEqual(card("Dips").loadCard()?.sets.first?.reps, "10")

        try await step()                                              // B S1 → log + repos → A
        XCTAssertNotNil(owner.logResults["Dips"])
        XCTAssertNotNil(active("Bench"))
        let run = restTimer.runID
        try await step()                                              // A S2 = fin réelle
        try await Task.sleep(nanoseconds: 1_000_000_000)
        try await settle()
        XCTAssertNotNil(owner.logResults["Bench"])
        XCTAssertEqual(restTimer.runID, run, "A n'a pas de repos")
        XCTAssertNotNil(active("Bench"), "Transition à la fin de la paire")
    }
}
