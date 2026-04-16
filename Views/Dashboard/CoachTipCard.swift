import SwiftUI

struct CoachTipCard: View {
    let tip: CoachTip

    private var accent: Color {
        switch tip.domain {
        case "nutrition": return .green
        case "training":  return .orange
        case "recovery":  return .blue
        case "sleep":     return .purple
        default:          return .orange
        }
    }

    private var icon: String {
        switch tip.domain {
        case "nutrition": return "fork.knife.circle.fill"
        case "training":  return "figure.strengthtraining.traditional"
        case "recovery":  return "heart.fill"
        case "sleep":     return "moon.fill"
        default:          return "lightbulb.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(accent)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("Coach du jour")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(accent)
                        .textCase(.uppercase)
                        .tracking(1)
                    Spacer()
                }
                Text(tip.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text(tip.body)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
        .padding(14)
        .background(accent.opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(accent.opacity(0.22), lineWidth: 1)
        )
        .cornerRadius(14)
    }
}
