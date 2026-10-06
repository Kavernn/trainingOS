import XCTest
import SwiftUI
import UIKit
import Combine
@testable import TrainingOS

/// Diagnostic reproduction using the real workout view and isolated local dates.
/// Network reads are intercepted; no production workout is created.
private final class LifecycleURLProtocol: URLProtocol {
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
private final class LifecyclePhase: ObservableObject {
    @Published var value: ScenePhase = .active
}

@MainActor
private struct LifecycleWorkoutHost: View {
    @ObservedObject var phase: LifecyclePhase
    let owner: SeanceViewModel
    let data: SeanceData
    let source: String
    var body: some View {
        NavigationStack {
            WorkoutSeanceView(data: data, vm: owner, isSecondSession: source == "evening",
                              isBonusSession: source == "bonus", isOverride: true)
        }
        .environment(\.scenePhase, phase.value)
    }
}

@MainActor
private struct LifecycleComposerHost: View {
    @ObservedObject var phase: LifecyclePhase
    let fixture: DayComposerStabilizationFixture
    let finish: DayComposerFinishCoordinator
    var body: some View {
        DayComposerActiveView(coordinator: fixture.coordinator, stabilizationBarrier: fixture.barrier,
                              finishCoordinator: finish, onDismiss: {})
            .environment(\.scenePhase, phase.value)
    }
}

@MainActor
final class ActiveWorkoutLifecycleTests: XCTestCase {
    func testCardBodyFitsSnapshotStackBudget() {
        let bytes = MemoryLayout<ExerciseCard.Body>.stride
        print("P0 ExerciseCard.Body stride: \(bytes) bytes")
        XCTAssertLessThan(bytes, 16_384, "The system background snapshot must not inline the entire expanded editor value into every ancestor stack frame")
    }

    func testDayComposerSnapshotCyclesPreserveEditorAndDoNotSubmit() async throws {
        let fixture = try DayComposerStabilizationFixture(morning: ["A", "B"], evening: ["A", "B"],
            reassignment: { try DayComposerSnapshot.transferring($0, id: $0[2].id, locked: false) })
        defer { fixture.cleanup() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var submissions = 0
        let finish = DayComposerFinishCoordinator(execution: fixture.coordinator, barrier: fixture.barrier,
            store: .init(baseDirectory: directory), inputs: .init(baseDirectory: directory.appendingPathComponent("inputs")),
            dependencies: .init(server: { _, source in
                .init(source: source, date: fixture.date, freshness: .fresh, observedNames: [], completion: .notCompleted)
            }, status: { _ in .notFound }, exercise: { _ in submissions += 1; return .invalidResponse },
                final: { _ in submissions += 1; return .invalidResponse }, completion: { _, _ in .unconfirmed }))
        let phase = LifecyclePhase()
        let host = UIHostingController(rootView: LifecycleComposerHost(phase: phase, fixture: fixture, finish: finish))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 932))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 200_000_000)
        func fields(_ view: UIView) -> [UITextField] {
            (view as? UITextField).map { [$0] } ?? view.subviews.flatMap(fields)
        }
        let field = try XCTUnwrap(fields(host.view).first { $0.isEnabled && $0.keyboardType == .decimalPad })
        field.text = "37"; field.sendActions(for: .editingChanged)
        let selected = fixture.coordinator.currentMemberID
        for _ in 0..<10 {
            for next in [ScenePhase.inactive, .background, .active] {
                phase.value = next; host.view.setNeedsLayout(); host.view.layoutIfNeeded()
                _ = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                    host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        XCTAssertEqual(fixture.coordinator.currentMemberID, selected)
        XCTAssertTrue(fields(host.view).contains { $0.text == "37" })
        XCTAssertEqual(submissions, 0)
        XCTAssertFalse(finish.dayCompleted)
        XCTAssertTrue(fixture.coordinator.morningVM.logResults.isEmpty)
        XCTAssertTrue(fixture.coordinator.eveningVM.logResults.isEmpty)
    }

    func testRealWorkoutViewRepeatedLifecycleKeepsActiveState() async throws {
        URLProtocol.registerClass(LifecycleURLProtocol.self)
        defer { URLProtocol.unregisterClass(LifecycleURLProtocol.self) }
        for source in ["morning", "evening", "bonus"] {
            let date = "lifecycle-\(UUID().uuidString)"
            defer {
                for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(date) {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
            let data = try APIService.decoder.decode(SeanceData.self,
                from: Fixtures.seanceDataJSON(today: "Lifecycle fixture", todayDate: date))
            let owner = SeanceViewModel(draftSessionType: source, followsActivePlanning: true)
            owner.seanceData = data
            owner.startSession()
            owner.sessionComment = "unsaved session comment"
            var log = ExerciseLogResult(name: "Completed fixture", weight: 42, reps: "8")
            log.isSecond = source == "evening"
            log.isBonus = source == "bonus"
            owner.logResults = [log.name: log]
            var reloads = 0
            owner.currentPlanningLoader = { _, _ in reloads += 1; return ("stale", data) }
            let editor = ExerciseViewModel(name: "Bench Press", scheme: "3x8", weightData: nil,
                isSecondSession: source == "evening", isBonusSession: source == "bonus", sessionDate: date)
            editor.initializeSets()
            editor.sets[0].weight = "37"
            editor.sets[0].reps = "9"
            XCTAssertEqual(editor.saveDraft(), .accepted)
            let skipped = ExerciseViewModel(name: "Skipped fixture", scheme: "1x5", weightData: nil,
                isSecondSession: source == "evening", isBonusSession: source == "bonus", sessionDate: date)
            skipped.initializeSets()
            skipped.setSkipped(true)
            let phase = LifecyclePhase()
            let host = UIHostingController(rootView: LifecycleWorkoutHost(phase: phase, owner: owner, data: data, source: source))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 932))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            host.view.layoutIfNeeded()
            let preset = UserDefaults.standard.object(forKey: RestTimerManager.presetKey)
            defer {
                RestTimerManager.shared.dismiss()
                if let preset { UserDefaults.standard.set(preset, forKey: RestTimerManager.presetKey) }
                else { UserDefaults.standard.removeObject(forKey: RestTimerManager.presetKey) }
            }
            for cycle in 0..<10 {
                if cycle == 5 { RestTimerManager.shared.start(seconds: 30, exerciseName: "Bench Press") }
                for next in [ScenePhase.inactive, .background, .active] {
                    phase.value = next
                    host.view.setNeedsLayout()
                    host.view.layoutIfNeeded()
                    try await Task.sleep(nanoseconds: 50_000_000)
                    if next == .background {
                        // Exercise the same synchronous render used by the app-switcher snapshot.
                        _ = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                            host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                        }
                        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
                        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
                    }
                    if next == .active { await owner.reloadCurrentPlanning() }
                }
            }
            XCTAssertEqual(reloads, 0)
            XCTAssertEqual(owner.sessionComment, "unsaved session comment")
            XCTAssertEqual(owner.logResults[log.name]?.weight, 42)
            XCTAssertFalse(owner.showSuccess)
            XCTAssertFalse(owner.isFinishing)
            XCTAssertEqual(owner.seanceData?.todayDate, date)
            XCTAssertEqual(editor.sets[0].weight, "37")
            XCTAssertTrue(skipped.isSkipped)
            XCTAssertTrue(RestTimerManager.shared.isRunning)
            XCTAssertGreaterThan(RestTimerManager.shared.remaining, 0)
            let saved = try XCTUnwrap(ExerciseDraftPersistence(date: date, sessionType: source, exerciseName: "Bench Press").load())
            XCTAssertEqual(saved.first?.weight, "37")
            XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: source), owner.sessionComment)
        }
    }
}
