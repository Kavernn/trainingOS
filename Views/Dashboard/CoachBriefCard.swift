import SwiftUI

struct CoachBriefCard: View {
    let brief: MorningBriefData
    let sessionCompletedToday: Bool
    var tip: CoachTip? = nil

    private var contextLabel: String {
        if sessionCompletedToday { return "Coach · Post-séance" }
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 5  && hour < 11 { return "Coach · Ce matin" }
        if hour >= 14 && hour < 18 { return "Coach · Pré-séance" }
        if hour >= 19              { return "Coach · Ce soir" }
        return "Coach"
    }

    private func tipColor(for domain: String) -> Color {
        switch domain {
        case "nutrition": return .green
        case "training":  return .orange
        case "recovery":  return .blue
        case "sleep":     return .purple
        default:          return .orange
        }
    }

    private func tipIcon(for domain: String) -> String {
        switch domain {
        case "nutrition": return "fork.knife.circle.fill"
        case "training":  return "figure.strengthtraining.traditional"
        case "recovery":  return "heart.fill"
        case "sleep":     return "moon.fill"
        default:          return "lightbulb.fill"
        }
    }

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .navigateToIntelligence, object: nil)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: "brain.head.profile")
                        .font(.appBody.weight(.semibold))
                        .foregroundColor(.orange)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(contextLabel)
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(.orange)
                            .textCase(.uppercase)
                            .tracking(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.appCaption.weight(.medium))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    Text(brief.message)
                        .font(.appLabel.weight(.regular))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)

                    if let tip {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 0.5)
                            .padding(.top, 4)
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: tipIcon(for: tip.domain))
                                .font(.appCaption)
                                .foregroundColor(tipColor(for: tip.domain))
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tip.title)
                                    .font(.appCaption.weight(.bold))
                                    .foregroundColor(.white.opacity(0.9))
                                Text(tip.body)
                                    .font(.appCaption)
                                    .foregroundColor(.gray)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(Color.orange.opacity(0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.orange.opacity(0.22), lineWidth: 1)
            )
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}
