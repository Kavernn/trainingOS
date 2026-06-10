import SwiftUI

// MARK: - Workout Bonus Badge

struct DayTypeBadge: View {
    let type: String
    var session: String?
    var effectiveCal: Double?
    var effectiveGluc: Double?

    private var config: (icon: String, label: String, color: Color) {
        switch type {
        case "heavy":    return ("dumbbell.fill",                       "Lourd · surplus léger",   .orange)
        case "moderate": return ("figure.strengthtraining.traditional", "Modéré · maintenance",    .yellow)
        case "light":    return ("figure.arms.open",                    "Léger · léger déficit",   Color(hex: "00BCD4"))
        default:         return ("moon.fill",                           "Repos · déficit",         .blue)
        }
    }

    var body: some View {
        let (icon, label, color) = config
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if let s = session, !s.isEmpty {
                        Text(s)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                        Text("· \(label)")
                            .font(.system(size: 12))
                            .foregroundColor(color)
                    } else {
                        Text(label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(color)
                    }
                }
                if let cal = effectiveCal, let gluc = effectiveGluc {
                    HStack(spacing: 8) {
                        Text("\(Int(cal)) kcal")
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.75))
                        Text("·")
                            .font(.system(size: 10))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("\(Int(gluc))g glucides")
                            .font(.appCaption)
                            .foregroundColor(.white.opacity(0.55))
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(color.opacity(0.1))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(color.opacity(0.25), lineWidth: 1))
    }
}
