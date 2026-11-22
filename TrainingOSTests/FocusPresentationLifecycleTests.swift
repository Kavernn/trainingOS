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

// MARK: - 4.3 : vraie WorkoutSeanceView, bascule sur place liste ↔ Focus

private final class FocusStubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
private struct FocusSessionHost: View {
    let owner: SeanceViewModel
    let data: SeanceData
    var body: some View {
        TabView {
            NavigationStack { WorkoutSeanceView(data: data, vm: owner, isOverride: true) }
                .tabItem { Label("Séance", systemImage: "dumbbell.fill") }
            Text("Programme").tabItem { Label("Programme", systemImage: "list.bullet.clipboard") }
        }
    }
}

@MainActor
final class FocusSessionSwitchTests: XCTestCase {

    private func tabBar(in view: UIView) -> UITabBar? {
        if let bar = view as? UITabBar { return bar }
        for sub in view.subviews { if let bar = tabBar(in: sub) { return bar } }
        return nil
    }
    private func tabBarVisible(_ window: UIWindow) -> Bool {
        guard let bar = tabBar(in: window) else { return false }
        return !bar.isHidden && bar.alpha > 0.01 && bar.convert(bar.bounds, to: window).intersects(window.bounds)
    }

    func testFocusEligibilityRepsOnly() {
        XCTAssertTrue(FocusEligibility.isEligible(trackingType: "reps"))
        for other in ["time", "mobility", "carry", "plyo", "protocol", "cardio"] {
            XCTAssertFalse(FocusEligibility.isEligible(trackingType: other), other)
        }
    }

    /// Nom unique par test : aucune collision avec les cartes d'un test précédent en libération différée.
    private var exercise = ""
    private var date = ""
    private var flagBefore: Any?
    private var host: UIHostingController<FocusSessionHost>!
    private var window: UIWindow!
    private var owner: SeanceViewModel!

    override func setUp() async throws {
        URLProtocol.registerClass(FocusStubURLProtocol.self)
        exercise = "Bench Press-\(UUID().uuidString.prefix(6))"
        date = "focus-session-\(UUID().uuidString)"
        flagBefore = UserDefaults.standard.object(forKey: FocusModePreference.key)
        UserDefaults.standard.set(false, forKey: FocusModePreference.key)
    }

    override func tearDown() async throws {
        window?.isHidden = true; window?.rootViewController = nil; window = nil; host = nil; owner = nil
        URLProtocol.unregisterClass(FocusStubURLProtocol.self)
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(date) {
            UserDefaults.standard.removeObject(forKey: key)
        }
        if let flagBefore { UserDefaults.standard.set(flagBefore, forKey: FocusModePreference.key) }
        else { UserDefaults.standard.removeObject(forKey: FocusModePreference.key) }
    }

    private var store: ExerciseDraftPersistence {
        ExerciseDraftPersistence(date: date, sessionType: "morning", exerciseName: exercise)
    }
    private var draftBytes: Data? {
        UserDefaults.standard.dictionaryRepresentation().keys
            .first { $0.contains(date) && $0.contains(exercise) }
            .flatMap { UserDefaults.standard.data(forKey: $0) }
    }
    private var liveCount: Int { ExerciseViewModel.debugLiveCount[exercise, default: 0] }
    /// L'instance affichée (non retirée).
    private func activeVM() throws -> ExerciseViewModel {
        let active = ExerciseViewModel.debugLive.filter { $0.name == exercise && !$0.isRetired }
        XCTAssertEqual(active.count, 1, "une seule instance active")
        return try XCTUnwrap(active.first)
    }
    private func reread() -> ExerciseViewModel {
        let vm = ExerciseViewModel(name: exercise, scheme: "4x5-7", weightData: nil, sessionDate: date)
        vm.initializeSets()
        return vm
    }

    private func settle() async throws {
        for _ in 0..<4 { host.view.setNeedsLayout(); host.view.layoutIfNeeded()
                         try await Task.sleep(nanoseconds: 150_000_000) }
    }
    /// Seul test qui vérifie la libération : SwiftUI libère l'ancienne carte avec retard (mesuré 1 à 3 s).
    private func awaitRelease(timeout: TimeInterval = 3.5) async throws -> Int {
        var peak = liveCount
        let deadline = Date().addingTimeInterval(timeout)
        while liveCount > 1 && Date() < deadline {
            host.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 100_000_000)
            peak = max(peak, liveCount)
        }
        return peak
    }

    /// Série en cours : S1 validée, S2 remplie puis annulée (undo) → courante = S2 malgré ses valeurs.
    private func mountSession() async throws {
        do {
            let editor = ExerciseViewModel(name: exercise, scheme: "4x5-7", weightData: nil, sessionDate: date)
            editor.initializeSets()
            editor.sets[0].weight = "80"; editor.sets[0].reps = "6"
            XCTAssertEqual(editor.markSet(0, done: true), .accepted)
            editor.sets[1].weight = "80"; editor.sets[1].reps = "5"
            XCTAssertEqual(editor.markSet(1, done: true), .accepted)
            XCTAssertEqual(editor.markSet(1, done: false), .accepted)
        }
        let data = try APIService.decoder.decode(SeanceData.self,
            from: Fixtures.seanceDataJSON(today: "Focus fixture", todayDate: date, exerciseName: exercise))
        owner = SeanceViewModel(draftSessionType: "morning", followsActivePlanning: true)
        owner.seanceData = data
        owner.startSession()
        owner.currentPlanningLoader = { _, _ in ("stale", data) }
        host = UIHostingController(rootView: FocusSessionHost(owner: owner, data: data))
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host; window.makeKeyAndVisible()
        try await settle()
        XCTAssertEqual(liveCount, 1)
    }

    func testInPlaceSwitchKeepsDraftDoneSingleViewModelAndHidesTabBar() async throws {
        try await mountSession()
        for cycle in 0..<6 {
            let focus = cycle.isMultiple(of: 2)
            UserDefaults.standard.set(focus, forKey: FocusModePreference.key)
            try await settle()
            let peak = try await awaitRelease()
            XCTAssertLessThanOrEqual(peak, 2, "pas d'accumulation, cycle \(cycle)")
            XCTAssertEqual(liveCount, 1, "ancienne carte libérée, cycle \(cycle)")
            XCTAssertEqual(tabBarVisible(window), !focus, "tab bar, cycle \(cycle) focus=\(focus)")
        }

        let saved = try XCTUnwrap(store.loadCard())
        XCTAssertEqual(saved.setStateVersion, 1)
        XCTAssertEqual(saved.sets[0].done, true)
        XCTAssertNil(saved.sets[1].done)                        // S2 annulée, non validée
        XCTAssertEqual(saved.sets[1].reps, "5")                 // valeurs conservées
        XCTAssertTrue(owner.logResults.isEmpty)                 // aucun log inventé par les bascules
        XCTAssertEqual(reread().currentSetIndex, 1)
    }

    /// Frappe en liste (écriture différée armée) puis changement du flag : la porte unique écrit d'abord.
    func testTypingThenImmediateSwitchKeepsValueInDraftAndNewCard() async throws {
        try await mountSession()
        let list = try activeVM()
        list.sets[1].reps = "7"
        XCTAssertTrue(list.hasPendingSetsPersistence)
        UserDefaults.standard.set(true, forKey: FocusModePreference.key)
        try await settle()
        XCTAssertEqual(store.loadCard()?.sets[1].reps, "7", "saisie écrite")
        XCTAssertTrue(list.isRetired)
        let focus = try activeVM()
        XCTAssertFalse(focus === list)
        XCTAssertEqual(focus.sets[1].reps, "7", "la carte Focus affiche la saisie")
        let bytes = try XCTUnwrap(draftBytes)
        try await Task.sleep(nanoseconds: 1_000_000_000)            // au-delà du debounce de 0,5 s
        XCTAssertEqual(draftBytes, bytes, "aucune écriture tardive")
    }

    /// La porte écrit AVANT la bascule : vérifié dans le même tour, avant tout rendu.
    func testPerformFlushesBeforeChange() async throws {
        try await mountSession()
        let list = try activeVM()
        list.sets[1].reps = "8"
        var seenInChange: String?
        FocusSwitch.perform { seenInChange = store.loadCard()?.sets[1].reps }
        XCTAssertEqual(seenInChange, "8")        // notification livrée de façon synchrone, avant la bascule
    }

    /// Saisie en attente → entrée immédiate en mode édition → valeur dans le brouillon relu.
    func testPendingTypingThenEditModeKeepsValue() async throws {
        try await mountSession()
        let list = try activeVM()
        list.sets[1].reps = "9"
        XCTAssertTrue(list.hasPendingSetsPersistence)
        NotificationCenter.default.post(name: FocusSwitch.debugToggleEditMode, object: nil)
        XCTAssertEqual(store.loadCard()?.sets[1].reps, "9", "écrit avant le passage en édition")
        try await settle()
        XCTAssertEqual(reread().sets[1].reps, "9")
        let bytes = try XCTUnwrap(draftBytes)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertEqual(draftBytes, bytes, "aucune écriture tardive")
    }

    /// L'ancienne instance, gardée en vie, tente d'écrire après la bascule (didSet de sessionNote).
    func testRetiredViewModelLateSessionNoteWriteIsIgnored() async throws {
        try await mountSession()
        let old = try activeVM()                                    // référence forte = libération différée
        UserDefaults.standard.set(true, forKey: FocusModePreference.key)
        try await settle()
        XCTAssertTrue(old.isRetired)
        XCTAssertFalse(try activeVM() === old)
        let bytes = try XCTUnwrap(draftBytes)
        old.sessionNote = "note tardive"                            // didSet → saveDraft
        XCTAssertEqual(old.saveDraft(), .skippedRetired)
        XCTAssertEqual(old.clearDraft(), .skippedRetired)
        XCTAssertNil(old.localPersistenceIssue)
        XCTAssertEqual(draftBytes, bytes, "brouillon inchangé")
    }
}
