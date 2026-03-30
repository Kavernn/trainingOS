import SwiftUI

struct ProactiveBannerCard: View {
    let alert: ProactiveAlert
    let onDismiss: () -> Void

    private var accentColor: Color {
        alert.severity == "warning" ? .orange : .blue
    }

    private var icon: String {
        switch alert.type {
        case "nutrition": return "fork.knife.circle.fill"
        case "recovery":  return "heart.fill"
        case "training":  return "figure.strengthtraining.traditional"
        default:          return "bell.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(alert.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text(alert.message)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.7))
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(accentColor.opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(accentColor.opacity(0.22), lineWidth: 1)
        )
        .cornerRadius(14)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
