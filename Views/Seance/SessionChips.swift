import SwiftUI

// MARK: - Mesocycle Chip
struct MesocycleChip: View {
    let info: MesocycleInfo

    private var color: Color {
        switch info.phaseLabel {
        case "S1–S2": return Color.statusBlue
        case "S3–S4": return Color.statusOrange
        case "S5–S6": return Color.appDanger
        case "S7":    return Color.appSuccess
        default:      return Color.statusPurple
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(info.phaseLabel)
                .font(.system(size: 10, weight: .black))
                .foregroundColor(color)
            Text("·")
                .font(.system(size: 10))
                .foregroundColor(.gray.opacity(0.5))
            Text(info.phase)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.appOnSurface.opacity(0.75))
            Text("·")
                .font(.system(size: 10))
                .foregroundColor(.gray.opacity(0.5))
            Text("RPE \(info.rpeTarget)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(color.opacity(0.9))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.25), lineWidth: 1))
        .cornerRadius(6)
    }
}

// MARK: - Readiness Chip

struct ReadinessChip: View {
    let score: Double
    let label: String
    let color: String

    private var swiftColor: Color {
        switch color {
        case "green":  return Color.appSuccess
        case "yellow": return Color.statusYellow
        case "orange": return Color.statusOrange
        case "red":    return Color.appDanger
        default:       return .gray
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.heart.fill")
                .font(.system(size: 10))
                .foregroundColor(swiftColor)
            Text("READINESS")
                .font(.appMicro.weight(.bold)).tracking(1)
                .foregroundColor(.gray)
            Text(String(format: "%.1f", score))
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundColor(swiftColor)
            Text("· \(label)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(swiftColor.opacity(0.8))
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(swiftColor.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(swiftColor.opacity(0.2), lineWidth: 1))
        .cornerRadius(8)
    }
}

// MARK: - Start Session Banner

struct StartSessionBanner: View {
    let onStart: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: {
            triggerNotificationFeedback(.success)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { onStart() }
        }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.forge.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "play.fill")
                        .font(.appBody.weight(.bold))
                        .foregroundColor(Color.forge)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Commencer la séance")
                        .font(.appBody.weight(.bold))
                        .foregroundColor(.appTextPrimary)
                    Text("Le chrono démarre maintenant")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.forge.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.forge.opacity(0.07))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(Color.forge.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(SpringButtonStyle(scale: 0.97))
    }
}
