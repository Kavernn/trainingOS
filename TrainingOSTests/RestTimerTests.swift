import XCTest
import Combine
import SwiftUI
@testable import TrainingOS

@MainActor
final class RestTimerTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var instant: Date!
    private var origin: Date!
    private var effects: [RestTimerManager.Effect] = []
    private var timer: RestTimerManager!

    override func setUp() async throws {
        suite = "RestTimerTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
        origin = Date(timeIntervalSince1970: 1_800_000_000)
        instant = origin
        effects = []
        timer = RestTimerManager(defaults: defaults, now: { [unowned self] in self.instant },
                                 effects: { [unowned self] in self.effects.append($0) })
    }

    override func tearDown() async throws {
        timer.stop()
        timer = nil
        defaults.removePersistentDomain(forName: suite)
    }

    private func tick(at elapsed: Double, id: UUID? = nil) {
        instant = origin.addingTimeInterval(elapsed)
        timer.tick(id: id ?? timer.runID!)
    }

    func testHalfSecondTicksKeepExactIntegerValuesWithoutGlobalPublications() {
        timer.start(seconds: 30, exerciseName: "A")
        var globalPublications = 0
        let subscription = timer.objectWillChange.sink { globalPublications += 1 }
        var values: [Int] = []
        for halfSecond in 1...12 {
            tick(at: Double(halfSecond) / 2)
            values.append(timer.remaining)
        }
        XCTAssertEqual(values, [30, 29, 29, 28, 28, 27, 27, 26, 26, 25, 25, 24])
        XCTAssertEqual(globalPublications, 0)
        XCTAssertTrue(timer.isRunning)
        print("Rest controlled: 12 ticks at 0.5...6 s; 6 value changes; 0 global publications. remaining is non-published. View redraws not measured.")
        withExtendedLifetime(subscription) {}
    }

    func testAdjustImmediatelyMovesDisplayOriginAndNotificationDeadline() {
        timer.start(seconds: 30, exerciseName: "A")
        tick(at: 5)
        instant = origin.addingTimeInterval(5.25)
        var dates: [Date?] = []
        let subscription = timer.$startDate.dropFirst().sink { dates.append($0) }
        timer.adjust(by: -10)
        XCTAssertEqual(timer.remaining, 15)
        XCTAssertEqual(timer.totalSeconds, 30)
        XCTAssertEqual(Int(instant.timeIntervalSince(timer.startDate!)), 15)
        XCTAssertEqual(dates.count, 1)
        XCTAssertEqual(effects.suffix(3), [.cancel, .cancel, .schedule(15)])
        tick(at: 5.5)
        XCTAssertEqual(timer.remaining, 15)
        timer.adjust(by: 20)
        XCTAssertEqual(timer.remaining, 35)
        XCTAssertEqual(timer.totalSeconds, 35)
        XCTAssertEqual(effects.last, .schedule(35))
        withExtendedLifetime(subscription) {}
    }

    func testStateTransitionsPublishEvenWhenRemainingIsUnchanged() {
        timer.start(seconds: 30, exerciseName: "A")
        var running: [Bool] = []
        var visible: [Bool] = []
        let a = timer.$isRunning.dropFirst().sink { running.append($0) }
        let b = timer.$isVisible.dropFirst().sink { visible.append($0) }
        timer.stop()
        XCTAssertEqual(timer.remaining, 30)
        XCTAssertNil(timer.startDate)
        instant = origin.addingTimeInterval(100)
        timer.resume()
        XCTAssertEqual(timer.remaining, 30)
        XCTAssertEqual(timer.startDate, instant)
        XCTAssertEqual(effects.last, .schedule(30))
        timer.start(seconds: 30, exerciseName: "B")
        XCTAssertEqual(timer.exerciseName, "B")
        timer.dismiss()
        XCTAssertEqual(running, [false, true, true, false])
        XCTAssertEqual(visible, [true, false])
        XCTAssertNil(timer.exerciseName)
        XCTAssertEqual(timer.remaining, 30)
        withExtendedLifetime([a, b]) {}
    }

    func testPauseResumeResetAndPausedAdjustmentKeepExistingRules() {
        timer.start(seconds: 30)
        tick(at: 8)
        timer.stop()
        XCTAssertEqual(timer.remaining, 22)
        instant = origin.addingTimeInterval(100)
        timer.resume()
        tick(at: 102)
        XCTAssertEqual(timer.remaining, 20)
        timer.reset()
        XCTAssertEqual(timer.remaining, 30)
        XCTAssertFalse(timer.isRunning)
        timer.adjust(by: -100)
        XCTAssertEqual(timer.remaining, 1)
        XCTAssertEqual(timer.totalSeconds, 1)
        timer.resume()
        XCTAssertEqual(effects.last, .schedule(1))
    }

    func testCountdownAndCompletionEffectsOccurOnceDespiteDuplicateTicks() {
        timer.start(seconds: 10)
        let id = timer.runID!
        effects = []
        for time in [7.0, 7.5, 8, 8.5, 9, 9.5, 10, 10.5, 11] {
            tick(at: time, id: id)
        }
        XCTAssertEqual(effects, [.countdown, .countdown, .countdown, .cancel, .finished])
        XCTAssertEqual(timer.remaining, 0)
        XCTAssertFalse(timer.isRunning)
        XCTAssertTrue(timer.isVisible)
        timer.resume()
        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(effects.count, 5)
    }

    func testStoppedAndReplacedCallbacksCannotCompleteNewRest() {
        timer.start(seconds: 10, exerciseName: "A")
        let old = timer.runID!
        timer.stop()
        tick(at: 50, id: old)
        timer.start(seconds: 30, exerciseName: "B")
        let current = timer.runID!
        effects = []
        tick(at: 100, id: old)
        XCTAssertEqual(timer.remaining, 30)
        XCTAssertTrue(timer.isRunning)
        XCTAssertEqual(timer.exerciseName, "B")
        XCTAssertTrue(effects.isEmpty)
        XCTAssertEqual(timer.runID, current)
        tick(at: 55, id: current)
        XCTAssertEqual(timer.remaining, 25)
    }

    func testMissedTicksRecalculateFromDateWithoutCatchingUpTickCount() {
        timer.start(seconds: 120)
        tick(at: 1)
        XCTAssertEqual(timer.remaining, 119)
        tick(at: 93.75)
        XCTAssertEqual(timer.remaining, 27)
        tick(at: 130)
        XCTAssertEqual(timer.remaining, 0)
        XCTAssertEqual(effects.filter { $0 == .finished }.count, 1)
    }

    func testBadgeBoundaryPreservesSiblingInputAndOwnerAcrossRestTransitions() async {
        let probe = RestPresentationProbe()
        let host = UIHostingController(rootView: RestPresentationHarness(timer: timer, probe: probe))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.layoutIfNeeded()
        await Task.yield()
        probe.entry?.wrappedValue = "42"
        host.view.layoutIfNeeded()
        await Task.yield()
        let owner = probe.owner
        XCTAssertNotNil(owner)
        for name in ["A", "B", "A"] {
            timer.start(seconds: 30, exerciseName: name)
            timer.adjust(by: -10)
            timer.stop()
            timer.resume()
            host.view.layoutIfNeeded()
            await Task.yield()
            XCTAssertEqual(probe.owner, owner)
            XCTAssertEqual(probe.entry?.wrappedValue, "42")
        }
        // Unmounting the presentation must not stop the shared authority.
        window.rootViewController = nil
        XCTAssertTrue(timer.isRunning)
    }

    func testUnmountedBadgeReleasesIsolatedManagerAcrossRepeatedMounts() async {
        weak var released: RestTimerManager?
        for _ in 0..<3 {
            autoreleasepool {
                let isolated = RestTimerManager(defaults: defaults, now: { Date() }, effects: { _ in })
                released = isolated
                let host = UIHostingController(rootView: AnyView(ExerciseRestCountdown(name: "A", timer: isolated)))
                host.loadViewIfNeeded()
                host.view.layoutIfNeeded()
                host.rootView = AnyView(EmptyView())
                host.view.layoutIfNeeded()
            }
            await Task.yield()
            XCTAssertNil(released)
        }
    }
}

@MainActor
private final class RestPresentationProbe {
    var entry: Binding<String>?
    var owner: ObjectIdentifier?
}

private final class RestPresentationOwner: ObservableObject {}

@MainActor
private struct RestPresentationHarness: View {
    let timer: RestTimerManager // Deliberately not observed by the parent, like ExerciseCard.
    let probe: RestPresentationProbe
    @State private var entry = "12"
    @StateObject private var owner = RestPresentationOwner()

    var body: some View {
        let _ = record()
        HStack {
            TextField("Reps", text: $entry)
            ExerciseRestCountdown(name: "A", timer: timer)
        }
    }

    private func record() {
        probe.entry = $entry
        probe.owner = ObjectIdentifier(owner)
    }
}
