import Foundation

/// Miroir de la logique dans Views/Stats/StatsBodyViews.swift:BodyProgressionColor
/// (fonction `direction` et `inDeadZone`). Les enums `Metric` / `Direction` sont
/// re-déclarés localement pour permettre une compilation standalone sans dépendre
/// de SwiftUI/Charts :
///
///     swiftc -parse-as-library tests/swift/BodyProgressionColorChecks.swift \
///       -o /tmp/BodyProgressionColorChecks && /tmp/BodyProgressionColorChecks
///
/// Toute divergence entre la logique du helper réel et ce miroir doit être
/// rectifiée manuellement. Objectif : verrouiller le comportement attendu
/// pour la matrice {3 métriques × goal nil/cut/bulk/maintain/recomp} et les
/// zones mortes.

enum Metric { case weight, bodyFat, waist }
enum Direction { case aligned, misaligned, neutral }

func inDeadZone(delta: Double, start: Double?, metric: Metric) -> Bool {
    let threshold: Double
    switch metric {
    case .weight:  threshold = (start.map { abs($0) * 0.01 }) ?? 1.0
    case .bodyFat: threshold = 0.5
    case .waist:   threshold = 1.0
    }
    return abs(delta) <= threshold
}

func direction(delta: Double, start: Double?, metric: Metric, goal: String?) -> Direction {
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

@main
struct BodyProgressionColorChecks {
    static func check(_ value: @autoclosure () -> Bool, _ label: String) {
        precondition(value(), label); print("PASS \(label)")
    }

    static func main() {
        // ── Matrice 3 métriques × goal nil/cut/bulk, delta hors zone morte ──

        // Masse grasse : goal IGNORÉ, "lower is better" partout
        for g in [nil, "cut", "bulk"] as [String?] {
            check(direction(delta: -1.0, start: nil, metric: .bodyFat, goal: g) == .aligned,
                  "bodyFat −1 pp hors ZM → aligned (goal=\(g ?? "nil"))")
            check(direction(delta: +1.0, start: nil, metric: .bodyFat, goal: g) == .misaligned,
                  "bodyFat +1 pp hors ZM → misaligned (goal=\(g ?? "nil"))")
        }

        // Tour de taille : goal IGNORÉ, "lower is better" partout
        for g in [nil, "cut", "bulk"] as [String?] {
            check(direction(delta: -2.0, start: nil, metric: .waist, goal: g) == .aligned,
                  "waist −2 cm hors ZM → aligned (goal=\(g ?? "nil"))")
            check(direction(delta: +2.0, start: nil, metric: .waist, goal: g) == .misaligned,
                  "waist +2 cm hors ZM → misaligned (goal=\(g ?? "nil"))")
        }

        // Poids : goal décide le sens aligné
        check(direction(delta: -5.0, start: 180.0, metric: .weight, goal: nil) == .neutral,
              "weight −5 lb hors ZM, goal nil → neutral (règle 'nil ne s'applique qu'au poids')")
        check(direction(delta: -5.0, start: 180.0, metric: .weight, goal: "cut") == .aligned,
              "weight −5 lb hors ZM, goal cut → aligned")
        check(direction(delta: -5.0, start: 180.0, metric: .weight, goal: "bulk") == .misaligned,
              "weight −5 lb hors ZM, goal bulk → misaligned")
        check(direction(delta: +5.0, start: 180.0, metric: .weight, goal: "cut") == .misaligned,
              "weight +5 lb hors ZM, goal cut → misaligned")
        check(direction(delta: +5.0, start: 180.0, metric: .weight, goal: "bulk") == .aligned,
              "weight +5 lb hors ZM, goal bulk → aligned")
        check(direction(delta: +5.0, start: 180.0, metric: .weight, goal: "maintain") == .misaligned,
              "weight +5 lb hors ZM, goal maintain → misaligned (dérive)")
        check(direction(delta: +5.0, start: 180.0, metric: .weight, goal: "recomp") == .misaligned,
              "weight +5 lb hors ZM, goal recomp → misaligned (dérive)")

        // ── Zones mortes ──
        // Weight : ±1 % de start. 180 lbs → ±1.8 lbs.
        check(direction(delta: +1.0, start: 180.0, metric: .weight, goal: "cut") == .neutral,
              "weight +1 lb dans ZM (±1,8 lb pour start=180) → neutral même goal cut")
        check(direction(delta: +2.0, start: 180.0, metric: .weight, goal: "cut") == .misaligned,
              "weight +2 lb hors ZM (±1,8 lb) → sort misaligned (goal cut)")
        // Repli start=nil → ±1 lb absolu
        check(direction(delta: +0.5, start: nil, metric: .weight, goal: "cut") == .neutral,
              "weight +0,5 lb start=nil → ZM ±1 lb (neutral)")
        check(direction(delta: +1.5, start: nil, metric: .weight, goal: "cut") == .misaligned,
              "weight +1,5 lb start=nil → hors ZM ±1 lb")
        // bodyFat ±0,5 pp absolu
        check(direction(delta: -0.4, start: nil, metric: .bodyFat, goal: nil) == .neutral,
              "bodyFat −0,4 pp ZM → neutral")
        check(direction(delta: -0.6, start: nil, metric: .bodyFat, goal: nil) == .aligned,
              "bodyFat −0,6 pp hors ZM → aligned")
        // waist ±1 cm absolu
        check(direction(delta: +0.9, start: nil, metric: .waist, goal: nil) == .neutral,
              "waist +0,9 cm ZM → neutral")
        check(direction(delta: +1.1, start: nil, metric: .waist, goal: nil) == .misaligned,
              "waist +1,1 cm hors ZM → misaligned")

        print("ALL CHECKS PASSED")
    }
}
