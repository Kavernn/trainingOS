import Foundation

/// Logique pure de la coloration des deltas Body — Foundation uniquement,
/// zéro dépendance SwiftUI. Permet au test standalone
/// `tests/swift/BodyProgressionColorChecks.swift` d'exercer le VRAI code
/// (compilé ensemble via swiftc), plutôt qu'un miroir divergeable.
///
/// L'extension `color(…)` qui mappe `Direction` vers `Color` vit dans
/// `Views/Stats/StatsBodyViews.swift` (fichier SwiftUI).
///
/// Règle : vert si le delta va dans le sens de l'objectif, forge sinon,
/// neutre si |delta| ≤ zone morte OU si le goal est inconnu (poids uniquement).
///
/// Zones mortes (absorbent le bruit de mesure) :
///  - weight   : ±1 % de `start` (eau/glycogène/sodium). Repli ±1 lb si start absent.
///  - bodyFat  : ±0,5 pp absolu (bruit Navy ±3 pp sur mesure isolée).
///  - waist    : ±1 cm absolu (respiration, technique).
///
/// Goal :
///  - cut      → perte alignée, prise contrariée
///  - bulk     → prise alignée, perte contrariée
///  - maintain, recomp → tout écart hors zone morte = contrarié (dérive)
///  - nil / inconnu    → neutre (jamais d'objectif par défaut)
///
/// Masse grasse et tour de taille : toujours "lower is better", goal ignoré.
enum BodyProgressionColor {
    enum Metric { case weight, bodyFat, waist }
    enum Direction { case aligned, misaligned, neutral }

    static func direction(delta: Double, start: Double?, metric: Metric, goal: String?) -> Direction {
        if inDeadZone(delta: delta, start: start, metric: metric) { return .neutral }
        switch metric {
        case .bodyFat, .waist:
            return delta < 0 ? .aligned : .misaligned
        case .weight:
            guard let g = goal?.lowercased() else { return .neutral }
            switch g {
            case "cut":                return delta < 0 ? .aligned : .misaligned
            case "bulk":               return delta > 0 ? .aligned : .misaligned
            case "maintain", "recomp": return .misaligned
            default:                   return .neutral
            }
        }
    }

    static func inDeadZone(delta: Double, start: Double?, metric: Metric) -> Bool {
        let threshold: Double
        switch metric {
        case .weight:  threshold = (start.map { abs($0) * 0.01 }) ?? 1.0
        case .bodyFat: threshold = 0.5
        case .waist:   threshold = 1.0
        }
        return abs(delta) <= threshold
    }
}
