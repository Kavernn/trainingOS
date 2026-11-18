import XCTest
import SwiftUI
import UIKit
import Combine
@testable import TrainingOS

/// Étape 4.1 : bascule liste ↔ Focus pendant une série en cours — rien n'est perdu,
/// jamais deux ExerciseViewModel sur le même exercice.
@MainActor
private final class FocusToggle: ObservableObject {
    @Published var presentation: ExerciseCardPresentation = .list
}

@MainActor
private struct FocusHost: View {
    @ObservedObject var toggle: FocusToggle
    @Binding var draftLog: ExerciseLogResult?
    @Binding var loggedLog: ExerciseLogResult?
    let date: String
    var body: some View {
        ScrollView {
            VStack {
                // Même position structurelle : seul le paramètre presentation change.
                ExerciseCard(name: "Focus draft", scheme: "4x5-8", weightData: nil,
                             logResult: $draftLog, isExpanded: true, sessionDate: date,
                             presentation: toggle.presentation)
                ExerciseCard(name: "Focus logged", scheme: "3x8", weightData: nil,
                             logResult: $loggedLog, sessionDate: date,
                             presentation: toggle.presentation)
            }
        }
    }
}

@MainActor
final class FocusPresentationLifecycleTests: XCTestCase {

    func testListFocusToggleKeepsDraftLogAndSingleViewModel() async throws {
        let date = "focus-\(UUID().uuidString)"
        defer {
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(date) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        // Série en cours : brouillon S1 (37 × 9), sauvegardé par un evm temporaire libéré ensuite.
        do {
            let editor = ExerciseViewModel(name: "Focus draft", scheme: "4x5-8", weightData: nil, sessionDate: date)
            editor.initializeSets()
            editor.sets[0].weight = "37"
            editor.sets[0].reps = "9"
            XCTAssertEqual(editor.saveDraft(), .accepted)
        }
        XCTAssertEqual(ExerciseViewModel.debugLiveCount["Focus draft", default: 0], 0)

        var draftLog: ExerciseLogResult? = nil
        var loggedLog: ExerciseLogResult? = ExerciseLogResult(name: "Focus logged", weight: 135, reps: "8,8,8")
        let toggle = FocusToggle()
        let host = UIHostingController(rootView: FocusHost(
            toggle: toggle,
            draftLog: Binding(get: { draftLog }, set: { draftLog = $0 }),
            loggedLog: Binding(get: { loggedLog }, set: { loggedLog = $0 }),
            date: date))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 932))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)

        for cycle in 0..<10 {
            toggle.presentation = cycle.isMultiple(of: 2) ? .focus : .list
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 50_000_000)
            XCTAssertEqual(ExerciseViewModel.debugLiveCount["Focus draft", default: 0], 1, "cycle \(cycle)")
            XCTAssertEqual(ExerciseViewModel.debugLiveCount["Focus logged", default: 0], 1, "cycle \(cycle)")
        }

        let saved = try XCTUnwrap(ExerciseDraftPersistence(date: date, sessionType: "morning",
                                                           exerciseName: "Focus draft").load())
        XCTAssertEqual(saved.first?.weight, "37")
        XCTAssertEqual(saved.first?.reps, "9")
        XCTAssertNil(draftLog)                                   // aucun log inventé par la bascule
        XCTAssertEqual(loggedLog?.weight, 135)                   // log existant intact
        XCTAssertEqual(loggedLog?.reps, "8,8,8")
    }
}
