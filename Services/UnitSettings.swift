import Foundation
import Combine

// App is lbs-only. This class is kept as a thin no-op wrapper so all call sites
// compile without changes. All conversions are identity functions.
final class UnitSettings: ObservableObject {
    static let shared = UnitSettings()
    private init() {}

    let objectWillChange = PassthroughSubject<Void, Never>()

    let isKg: Bool = false
    let label: String = "lbs"
    let distanceUnit: String = "MI"

    func display(_ lbs: Double) -> Double { lbs }
    func toStorage(_ value: Double) -> Double { value }
    func format(_ lbs: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f lbs", lbs)
    }
    func inputStr(_ lbs: Double) -> String { String(format: "%.1f", lbs) }
}
