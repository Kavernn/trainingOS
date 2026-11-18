import XCTest
@testable import TrainingOS

/// E point 4 : message « à battre » avec les vrais seuils, volume toujours « de volume ».
final class OverloadMessageTests: XCTestCase {

    private func g(_ n: Int) -> String { OverloadMessage.grouped(n) }

    func testNotReachedShowsRealThresholdsAndWhatIsMissing() {
        let text = OverloadMessage.text(targetReps: 24, currentReps: 16, targetVolume: 2480,
                                        currentVolume: 2140, reached: false, unit: "lbs")
        XCTAssertEqual(text, "À battre : 25 reps ou plus de \(g(2480)) lbs de volume"
                           + " · il manque 9 reps ou au moins 341 lbs de volume")
    }

    func testVolumeMissingIsMinimalStrictlyGreaterInteger() {
        let fractional = OverloadMessage.text(targetReps: nil, currentReps: 0, targetVolume: 2480,
                                              currentVolume: 2140.4, reached: false, unit: "lbs")
        XCTAssertTrue(fractional.hasSuffix("au moins 340 lbs de volume"))   // 339,6 → 340 suffit
    }

    func testReachedState() {
        XCTAssertEqual(OverloadMessage.text(targetReps: 24, currentReps: 25, targetVolume: 2480,
                                            currentVolume: 2600, reached: true, unit: "lbs"),
                       "Dernière fois battue : 24 reps · \(g(2480)) lbs de volume")
    }

    func testRepsOnlyAndNoTarget() {
        XCTAssertEqual(OverloadMessage.text(targetReps: 24, currentReps: 30, targetVolume: nil,
                                            currentVolume: 0, reached: false, unit: "lbs"),
                       "À battre : 25 reps · il manque 1 rep")
        XCTAssertEqual(OverloadMessage.text(targetReps: nil, currentReps: 0, targetVolume: nil,
                                            currentVolume: 0, reached: false, unit: "lbs"), "")
    }
}
