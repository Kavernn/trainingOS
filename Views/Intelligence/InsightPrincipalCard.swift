import SwiftUI

struct InsightPrincipalCard: View {
    let insight: DailyInsight
    var onNavigateToProgramme: (() -> Void)? = nil

    private var accent: Color {
        switch insight.type {
        case "alert":       return insight.priority == 1 ? .red : .orange
        case "opportunity": return .green
        case "programme":   return .blue
        default:            return .purple
        }
    }

    private var typeLabel: String {
        switch insight.type {
        case "alert":       return "Alerte"
        case "opportunity": return "Opportunité"
        case "programme":   return "Programme"
        default:            return "Insight du jour"
        }
    }

    var body: some View {
        Button(action: navigate) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: insight.icon.isEmpty ? "lightbulb.fill" : insight.icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(accent)
                    Text(typeLabel.uppercased())
                        .font(.system(size: 10, weight: .black))
                        .tracking(1.5)
                        .foregroundColor(accent)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(insight.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(insight.body)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.78))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    if !insight.source.isEmpty {
                        Text(insight.source)
                            .font(.system(size: 11))
                            .foregroundColor(accent.opacity(0.7))
                    }
                    Spacer()
                    if insight.action != "coach" {
                        HStack(spacing: 3) {
                            Text("Voir")
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(accent)
                    }
                }
            }
            .padding(14)
            .background(accent.opacity(0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(accent.opacity(0.25), lineWidth: 1)
            )
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }

    private func navigate() {
        switch insight.action {
        case "seance":
            NotificationCenter.default.post(name: .navigateToSeance, object: nil)
        case "stats":
            NotificationCenter.default.post(name: .navigateToRecovery, object: nil)
        case "programme":
            onNavigateToProgramme?()
        default:
            break
        }
    }
}
