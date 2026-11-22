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
    /// Charge → « 61.25 kg », « 60 kg », « 62.5 kg » : affiché = enregistré (même règle que inputStr).
    /// `decimals` explicite = arrondi voulu par l'appelant (e1RM, volume, poids du corps) : inchangé.
    func format(_ lbs: Double, decimals: Int? = nil) -> String {
        guard let decimals else { return "\(Self.decimalString(display(lbs))) \(label)" }
        return String(format: "%.\(decimals)f \(label)", display(lbs))
    }
    func inputStr(_ lbs: Double) -> String { Self.decimalString(display(lbs)) }

    /// Valeur saisie/enregistrée → texte : jusqu'à 2 décimales, sans zéro inutile
    /// (61.25, 60, 62.5). Affiché = enregistré : pas d'arrondi à 1 décimale (61.25 ≠ 61.3).
    /// L'arrondi à 2 décimales n'absorbe que le bruit de conversion kg↔lbs.
    static func decimalString(_ value: Double) -> String {
        let v = (value * 100).rounded() / 100
        if v.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(v))" }
        var s = String(format: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }

    /// Formatte un tonnage (lbs backend) en "82 050 lbs" / "37 220 kg".
    /// Conversion via `display`, groupage par espace insécable, label kg/lbs.
    /// Source unique pour tous les call sites Stats/Séance (Charge,
    /// Ma Semaine, SessionReportMetric). Jamais de division par 1000 ni
    /// de suffixe "t" codé en dur — ces chiffres sont des sommes de poids
    /// stockées en lbs, pas des tonnes.
    func formatTonnage(_ lbs: Double) -> String {
        let displayed = display(lbs)
        let number = NumberFormatter.spaceGrouped.string(from: NSNumber(value: displayed))
            ?? String(format: "%.0f", displayed)
        return "\(number) \(label)"
    }
}
