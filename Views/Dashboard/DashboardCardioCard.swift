import SwiftUI

struct DashboardCardioCard: View {
    let entry: CardioEntry

    private var accentColor: Color {
        switch entry.type {
        case "course": return .statusCyan
        case "vélo":   return .statusCyan
        case "marche": return .statusGreen
        default:       return .statusBlue
        }
    }

    private var icon: String {
        switch entry.type {
        case "course": return "figure.run"
        case "vélo":   return "figure.outdoor.cycle"
        case "marche": return "figure.walk"
        default:       return "figure.mixed.cardio"
        }
    }

    private var typeLabel: String {
        (entry.type ?? "cardio").capitalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(accentColor.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.appHeadline.weight(.semibold))
                        .foregroundColor(accentColor)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("CARDIO")
                        .font(.appMicro.weight(.black))
                        .tracking(1.4)
                        .foregroundColor(accentColor)
                    Text(typeLabel)
                        .font(.appLabel.weight(.bold))
                        .foregroundColor(Color.appOnSurface)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.appLabel)
                    .foregroundColor(Color.appSuccess)
            }

            Spacer(minLength: 0)

            HStack(alignment: .bottom) {
                if let duration = entry.durationMin {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(duration >= 60
                            ? String(format: "%dh%02d", Int(duration) / 60, Int(duration) % 60)
                            : String(format: "%.0f min", duration))
                            .font(.appHeadline.weight(.black))
                            .foregroundColor(accentColor)
                        Text("Durée")
                            .font(.appMicro.weight(.medium))
                            .foregroundColor(Color.appTextSecondary)
                    }
                }
                Spacer()
                Text("Complété")
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(Color.appSuccess)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(accentColor.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(accentColor.opacity(0.16), lineWidth: 1)
        )
        .glassCard(cornerRadius: 14)
    }
}
