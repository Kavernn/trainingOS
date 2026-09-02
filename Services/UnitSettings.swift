import Foundation
import Combine

final class UnitSettings: ObservableObject {
    static let shared = UnitSettings()
    private init() {
        self.isKg = UserDefaults.standard.bool(forKey: "unit_is_kg")
    }

    @Published var isKg: Bool {
        didSet { UserDefaults.standard.set(isKg, forKey: "unit_is_kg") }
    }

    var label: String { isKg ? "kg" : "lbs" }
    var distanceUnit: String { "MI" }

    // Storage is always lbs internally.
    // display() converts from lbs → display unit.
    // toStorage() converts from user input → lbs for storage.
    func display(_ lbs: Double) -> Double { isKg ? lbs * 0.453592 : lbs }
    func toStorage(_ value: Double) -> Double { isKg ? value / 0.453592 : value }
    func format(_ lbs: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f \(label)", display(lbs))
    }
    func inputStr(_ lbs: Double) -> String {
        let v = display(lbs)
        return v.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(v))"
            : String(format: "%.1f", v)
    }
}
