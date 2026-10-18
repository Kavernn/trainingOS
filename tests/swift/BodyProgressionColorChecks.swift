import Foundation

/// Exerce le VRAI code de `Utilities/BodyProgressionCore.swift`. Pas de
/// miroir : les deux fichiers sont compilés ensemble en standalone.
///
///     swiftc -parse-as-library \
///       Utilities/BodyProgressionCore.swift \
///       tests/swift/BodyProgressionColorChecks.swift \
///       -o /tmp/BodyProgressionColorChecks && /tmp/BodyProgressionColorChecks
///
/// Vérifie la matrice {3 métriques × goal nil/cut/bulk/maintain/recomp}
/// et les zones mortes par métrique.

@main
struct BodyProgressionColorChecks {
    typealias BPC = BodyProgressionColor

    static func check(_ value: @autoclosure () -> Bool, _ label: String) {
        precondition(value(), label); print("PASS \(label)")
    }

    static func main() {
        // ── Matrice 3 métriques × goal nil/cut/bulk, delta hors zone morte ──

        // Masse grasse : goal IGNORÉ, "lower is better" partout
        for g in [nil, "cut", "bulk"] as [String?] {
            check(BPC.direction(delta: -1.0, start: nil, metric: .bodyFat, goal: g) == .aligned,
                  "bodyFat −1 pp hors ZM → aligned (goal=\(g ?? "nil"))")
            check(BPC.direction(delta: +1.0, start: nil, metric: .bodyFat, goal: g) == .misaligned,
                  "bodyFat +1 pp hors ZM → misaligned (goal=\(g ?? "nil"))")
        }

        // Tour de taille : goal IGNORÉ, "lower is better" partout
        for g in [nil, "cut", "bulk"] as [String?] {
            check(BPC.direction(delta: -2.0, start: nil, metric: .waist, goal: g) == .aligned,
                  "waist −2 cm hors ZM → aligned (goal=\(g ?? "nil"))")
            check(BPC.direction(delta: +2.0, start: nil, metric: .waist, goal: g) == .misaligned,
                  "waist +2 cm hors ZM → misaligned (goal=\(g ?? "nil"))")
        }

        // Poids : goal décide le sens aligné
        check(BPC.direction(delta: -5.0, start: 180.0, metric: .weight, goal: nil) == .neutral,
              "weight −5 lb hors ZM, goal nil → neutral (règle 'nil ne s'applique qu'au poids')")
        check(BPC.direction(delta: -5.0, start: 180.0, metric: .weight, goal: "cut") == .aligned,
              "weight −5 lb hors ZM, goal cut → aligned")
        check(BPC.direction(delta: -5.0, start: 180.0, metric: .weight, goal: "bulk") == .misaligned,
              "weight −5 lb hors ZM, goal bulk → misaligned")
        check(BPC.direction(delta: +5.0, start: 180.0, metric: .weight, goal: "cut") == .misaligned,
              "weight +5 lb hors ZM, goal cut → misaligned")
        check(BPC.direction(delta: +5.0, start: 180.0, metric: .weight, goal: "bulk") == .aligned,
              "weight +5 lb hors ZM, goal bulk → aligned")
        check(BPC.direction(delta: +5.0, start: 180.0, metric: .weight, goal: "maintain") == .misaligned,
              "weight +5 lb hors ZM, goal maintain → misaligned (dérive)")
        check(BPC.direction(delta: +5.0, start: 180.0, metric: .weight, goal: "recomp") == .misaligned,
              "weight +5 lb hors ZM, goal recomp → misaligned (dérive)")

        // ── Zones mortes ──
        // Weight : ±1 % de start. 180 lbs → ±1.8 lbs.
        check(BPC.direction(delta: +1.0, start: 180.0, metric: .weight, goal: "cut") == .neutral,
              "weight +1 lb dans ZM (±1,8 lb pour start=180) → neutral même goal cut")
        check(BPC.direction(delta: +2.0, start: 180.0, metric: .weight, goal: "cut") == .misaligned,
              "weight +2 lb hors ZM (±1,8 lb) → sort misaligned (goal cut)")
        // Repli start=nil → ±1 lb absolu
        check(BPC.direction(delta: +0.5, start: nil, metric: .weight, goal: "cut") == .neutral,
              "weight +0,5 lb start=nil → ZM ±1 lb (neutral)")
        check(BPC.direction(delta: +1.5, start: nil, metric: .weight, goal: "cut") == .misaligned,
              "weight +1,5 lb start=nil → hors ZM ±1 lb")
        // bodyFat ±0,5 pp absolu
        check(BPC.direction(delta: -0.4, start: nil, metric: .bodyFat, goal: nil) == .neutral,
              "bodyFat −0,4 pp ZM → neutral")
        check(BPC.direction(delta: -0.6, start: nil, metric: .bodyFat, goal: nil) == .aligned,
              "bodyFat −0,6 pp hors ZM → aligned")
        // waist ±1 cm absolu
        check(BPC.direction(delta: +0.9, start: nil, metric: .waist, goal: nil) == .neutral,
              "waist +0,9 cm ZM → neutral")
        check(BPC.direction(delta: +1.1, start: nil, metric: .waist, goal: nil) == .misaligned,
              "waist +1,1 cm hors ZM → misaligned")

        // ── Appel direct inDeadZone pour cover le prédicat seul ──
        check(BPC.inDeadZone(delta: 0.0, start: 180.0, metric: .weight) == true,
              "inDeadZone(0, 180, weight) → true")
        check(BPC.inDeadZone(delta: 3.0, start: 180.0, metric: .weight) == false,
              "inDeadZone(3, 180, weight) → false")

        print("ALL CHECKS PASSED")
    }
}
