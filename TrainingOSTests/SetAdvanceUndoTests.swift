import XCTest
@testable import TrainingOS

/// Étape 4.2 : undo d'une série intermédiaire — n'arrête que le repos lancé par cette avancée.
@MainActor
final class SetAdvanceUndoTests: XCTestCase {
    private var instant = Date(timeIntervalSince1970: 1_800_000_000)
    private var timer: RestTimerManager!
    private var suite = "SetAdvanceUndoTests.\(UUID())"

    override func setUp() async throws {
        timer = RestTimerManager(defaults: UserDefaults(suiteName: suite)!, now: { [unowned self] in self.instant },
                                 effects: { _ in })
    }

    override func tearDown() async throws {
        timer.stop(); timer = nil
        UserDefaults().removePersistentDomain(forName: suite)
    }

    func testStopsOwnRestAndGoesBackOneSet() throws {
        timer.start(seconds: 90, exerciseName: "Row")
        let undo = SetAdvanceUndo(fromIndex: 1, restRun: timer.runID)
        let r = try XCTUnwrap(undo.resolve(currentIndex: 2, activeRun: timer.runID))
        XCTAssertEqual(r.index, 1)
        XCTAssertTrue(r.stopsRest)
    }

    func testNeverStopsAManualRestStartedAfterwards() throws {
        timer.start(seconds: 90, exerciseName: "Row")
        let undo = SetAdvanceUndo(fromIndex: 1, restRun: timer.runID)
        timer.start(seconds: 120, exerciseName: "Row")             // repos manuel → nouveau run
        let r = try XCTUnwrap(undo.resolve(currentIndex: 2, activeRun: timer.runID))
        XCTAssertFalse(r.stopsRest)
        XCTAssertEqual(r.index, 1)
    }

    func testNoRestLaunchedStopsNothing() throws {
        timer.start(seconds: 90, exerciseName: "Other")            // repos d'un autre exercice
        let r = try XCTUnwrap(SetAdvanceUndo(fromIndex: 0, restRun: nil)
            .resolve(currentIndex: 1, activeRun: timer.runID))
        XCTAssertFalse(r.stopsRest)
    }

    func testStaleUndoIsIgnored() {
        let undo = SetAdvanceUndo(fromIndex: 1, restRun: nil)
        XCTAssertNil(undo.resolve(currentIndex: 3, activeRun: nil))   // une autre avancée a eu lieu
        XCTAssertNil(undo.resolve(currentIndex: 1, activeRun: nil))   // déjà annulé / remonté
    }

    func testAdjustedRestKeepsItsRunSoUndoStopsIt() throws {
        timer.start(seconds: 90, exerciseName: "Row")
        let undo = SetAdvanceUndo(fromIndex: 1, restRun: timer.runID)
        timer.adjust(by: 30)                                         // +30 s : même repos, même run
        XCTAssertTrue(try XCTUnwrap(undo.resolve(currentIndex: 2, activeRun: timer.runID)).stopsRest)
    }
}
