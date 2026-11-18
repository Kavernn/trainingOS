import XCTest
import SwiftUI
@testable import TrainingOS

/// Étape 4.0 : token appFocus — plancher de graisse .semibold via ordre explicite.
final class AppFocusTokenTests: XCTestCase {

    func testWeightFloorKeepsHeavierAndRaisesLighter() {
        XCTAssertEqual(FontWeightOrder.atLeast(.thin, .semibold), .semibold)      // Monochrome
        XCTAssertEqual(FontWeightOrder.atLeast(.regular, .semibold), .semibold)   // Liquid Glass
        XCTAssertEqual(FontWeightOrder.atLeast(.medium, .semibold), .semibold)
        XCTAssertEqual(FontWeightOrder.atLeast(.semibold, .semibold), .semibold)
        XCTAssertEqual(FontWeightOrder.atLeast(.bold, .semibold), .bold)
        XCTAssertEqual(FontWeightOrder.atLeast(.black, .semibold), .black)        // Sin City, Brutalist
    }

    func testOrderIsStrictlyAscendingAndComplete() {
        XCTAssertEqual(FontWeightOrder.ascending.count, 9)
        XCTAssertEqual(Set(FontWeightOrder.ascending.map { "\($0)" }).count, 9)
        XCTAssertEqual(FontWeightOrder.ascending.first, .ultraLight)
        XCTAssertEqual(FontWeightOrder.ascending.last, .black)
    }
}
