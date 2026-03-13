import Foundation
import Combine

final class UnitSettings: ObservableObject {
    static let shared = UnitSettings()

    @Published var isKg: Bool {
        didSet { UserDefaults.standard.set(isKg, forKey: "unit_is_kg") }
    }

    private init() {
        isKg = false
        UserDefaults.standard.set(false, forKey: "unit_is_kg")
    }

    var label: String { isKg ? "kg" : "lbs" }

    // Convert a stored-lbs value to the display value
    func display(_ lbs: Double) -> Double { isKg ? lbs * 0.453592 : lbs }

    // Convert a user-input display value back to lbs for storage
    func toStorage(_ value: Double) -> Double { isKg ? value / 0.453592 : value }

    // Formatted string with unit label
    func format(_ lbs: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f \(label)", display(lbs))
    }

    // Initial string for an input field (stored lbs → display unit)
    func inputStr(_ lbs: Double) -> String { String(format: "%.1f", display(lbs)) }
}
