import SwiftUI

// MARK: - Coach Insight Card (Coach brief + proactive alert, priority: alert > coach)

struct CoachInsightCard: View {
    let brief: MorningBriefData?
    let sessionCompletedToday: Bool
    var alert: ProactiveAlert? = nil
    var onDismissAlert: (() -> Void)? = nil

    private var contextLabel: String {
        if sessionCompletedToday { return "Coach · Post-séance" }
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 5  && hour < 11 { return "Coach · Ce matin" }
        if hour >= 14 && hour < 18 { return "Coach · Pré-séance" }
        if hour >= 19              { return "Coach · Ce soir" }
        return "Coach"
    }

    var body: some View {
        if let alert {
            alertContent(alert)
        } else if let brief {
            coachContent(brief)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func alertContent(_ alert: ProactiveAlert) -> some View {
        let accentColor: Color = alert.severity == "warning" ? Color.appWarning : Color.appInfo
        let alertIcon: String = {
            switch alert.type {
            case "nutrition": return "fork.knife.circle.fill"
            case "recovery":  return "heart.fill"
            case "training":  return "figure.strengthtraining.traditional"
            default:          return "bell.fill"
            }
        }()
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(accentColor.opacity(0.14))
                    .frame(width: 42, height: 42)
                Image(systemName: alertIcon)
                    .font(.appHeadline.weight(.semibold))
                    .foregroundColor(accentColor)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("COACH · ALERTE")
                    .font(.appMicro.weight(.black))
                    .tracking(1.5)
                    .foregroundColor(accentColor)
                Text(alert.title)
                    .font(.appHeadline.weight(.bold))
                    .foregroundColor(Color.appOnSurface)
                Text(alert.message)
                    .font(.appLabel)
                    .foregroundColor(Color.appTextSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: { onDismissAlert?() }) {
                Image(systemName: "xmark")
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(Color.appTextMuted)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(accentColor.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(accentColor.opacity(0.22), lineWidth: 1)
        )
        .glassCard(cornerRadius: 16)
    }

    @ViewBuilder
    private func coachContent(_ brief: MorningBriefData) -> some View {
        Button {
            AppState.shared.pendingDeepLink = "intelligence"
        } label: {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.forge.opacity(0.14))
                        .frame(width: 42, height: 42)
                    Image(systemName: "brain.head.profile")
                        .font(.appHeadline.weight(.semibold))
                        .foregroundColor(Color.forge)
                }
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(contextLabel)
                            .font(.appMicro.weight(.black))
                            .foregroundColor(Color.forge)
                            .textCase(.uppercase)
                            .tracking(1.5)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.appCaption.weight(.medium))
                            .foregroundColor(Color.appTextMuted)
                    }
                    Text(brief.message)
                        .font(.appBody.weight(.medium))
                        .foregroundColor(Color.appOnSurface)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }
            }
            .padding(16)
            .background(Color.forge.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.forge.opacity(0.20), lineWidth: 1)
            )
            .cornerRadius(16)
            .glassCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }
}
