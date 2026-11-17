import XCTest
import UIKit
@testable import TrainingOS

@MainActor
final class ScreenAwakeTests: XCTestCase {
    private var ids: [UUID] = []

    override func tearDown() async throws {
        for id in ids { ScreenAwake.set(false, for: id) }
        ids = []
    }

    private func holder() -> UUID { let id = UUID(); ids.append(id); return id }

    func testLastHolderReleasingRestoresIdleTimer() {
        let morning = holder(), evening = holder()
        ScreenAwake.set(true, for: morning)
        ScreenAwake.set(true, for: evening)          // transition : B apparaît avant que A disparaisse
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)

        ScreenAwake.set(false, for: morning)
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)   // un détenteur reste

        ScreenAwake.set(false, for: evening)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)  // veille rétablie
    }

    func testReleasingUnknownOrTwiceIsHarmless() {
        let a = holder()
        ScreenAwake.set(false, for: holder())         // jamais inséré
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
        ScreenAwake.set(true, for: a)
        ScreenAwake.set(true, for: a)                 // ré-entrée idempotente
        ScreenAwake.set(false, for: a)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
        XCTAssertTrue(ScreenAwake.holders.isEmpty)
    }
}
