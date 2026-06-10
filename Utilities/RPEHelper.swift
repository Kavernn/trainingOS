import SwiftUI

// MARK: - RPEHelper — Source de vérité RIR/RPE

enum RPEHelper {

    // MARK: - RIR Option

    struct RIROption: Identifiable {
        let id: Int
        let rir: Int
        let label: String
        let shortLabel: String
        let rpe: Double

        var color: Color {
            switch rir {
            case 0: return Color(hex: "FF3B30")
            case 1: return Color(hex: "FF6B35")
            case 2: return Color(hex: "FF9500")
            case 3: return Color(hex: "FFCC00")
            default: return Color(hex: "34C759")
            }
        }
    }

    static let options: [RIROption] = [
        RIROption(id: 0, rir: 0, label: "Max / Échec",       shortLabel: "0",  rpe: 10),
        RIROption(id: 1, rir: 1, label: "Très dur",           shortLabel: "1",  rpe: 9),
        RIROption(id: 2, rir: 2, label: "Dur mais propre",    shortLabel: "2",  rpe: 8),
        RIROption(id: 3, rir: 3, label: "Challenge contrôlé", shortLabel: "3",  rpe: 7),
        RIROption(id: 4, rir: 4, label: "Trop facile",        shortLabel: "4+", rpe: 6),
    ]

    // MARK: - Conversions

    static func rirToRPE(_ rir: Int) -> Double {
        switch rir {
        case 0: return 10
        case 1: return 9
        case 2: return 8
        case 3: return 7
        default: return 6  // 4+
        }
    }

    // Maps any RPE value back to a RIR bucket (for tile selection)
    static func rirFromRPE(_ rpe: Double) -> Int {
        if rpe >= 9.5 { return 0 }
        if rpe >= 8.5 { return 1 }
        if rpe >= 7.5 { return 2 }
        if rpe >= 6.5 { return 3 }
        return 4
    }

    static func option(for rir: Int) -> RIROption {
        options.first { $0.rir == min(rir, 4) } ?? options[4]
    }

    // MARK: - Color

    static func color(for rpe: Double) -> Color {
        if rpe >= 9.5 { return Color(hex: "FF3B30") }
        if rpe >= 8.5 { return Color(hex: "FF6B35") }
        if rpe >= 7.5 { return Color(hex: "FF9500") }
        if rpe >= 6.5 { return Color(hex: "FFCC00") }
        return Color(hex: "34C759")
    }

    // MARK: - Feedback contextuel

    static func feedback(for rpe: Double) -> String {
        switch rpe {
        case ..<6.5:
            return "Trop facile pour progresser efficacement. On peut monter la prochaine fois."
        case 6.5..<7.5:
            return "Bon effort contrôlé. Idéal pour accumuler du volume propre."
        case 7.5..<8.5:
            return "Zone optimale. Excellent niveau d'effort pour l'hypertrophie."
        case 8.5..<9.5:
            return "Très dur. Bon pour pousser — à surveiller si ça arrive trop souvent."
        default:
            return "Échec ou quasi-échec. À utiliser avec parcimonie sur les gros lifts."
        }
    }

    static func progressionHint(for rpe: Double) -> String? {
        switch rpe {
        case ..<6.5:
            return "Augmente la charge ou ajoute 1–2 reps la prochaine fois."
        case 8.5..<9.5:
            return "Maintiens — progresse seulement si les reps étaient au haut de ta range."
        case 9.5...:
            return "Garde ou réduis légèrement si la technique souffre."
        default:
            return nil  // zone optimale, pas de hint nécessaire
        }
    }

    // MARK: - RIR Tiles View (composant réutilisable)

    struct RIRTiles: View {
        @Binding var rir: Int
        var showLabels: Bool = false
        var disabled: Bool = false

        var body: some View {
            HStack(spacing: 2) {
                ForEach(RPEHelper.options) { opt in
                    let effectiveRIR = min(rir, 4)
                    let selected = opt.rir == effectiveRIR
                    Button {
                        rir = opt.rir
                        triggerImpact(style: .light)
                    } label: {
                        if showLabels {
                            VStack(spacing: 3) {
                                Text(opt.shortLabel)
                                    .font(.appBody.weight(.black))
                                    .foregroundColor(selected ? .black : .white)
                                Text(opt.label)
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(selected ? .black.opacity(0.65) : .gray.opacity(0.45))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(selected ? opt.color : Color.appSurfaceInset)
                            .cornerRadius(10)
                        } else {
                            Text(opt.shortLabel)
                                .font(.appMicro.weight(.black))
                                .foregroundColor(selected ? .black : .gray.opacity(0.5))
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .background(selected ? opt.color : Color.appSurfaceInset)
                                .cornerRadius(5)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(disabled)
                }
            }
        }
    }
}
