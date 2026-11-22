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
}
