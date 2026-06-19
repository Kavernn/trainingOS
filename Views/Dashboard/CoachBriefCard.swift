import SwiftUI

// MARK: - Coach Insight Card (Coach brief + proactive alert, priority: alert > coach)

struct CoachInsightCard: View {
    let brief: MorningBriefData?
    let sessionCompletedToday: Bool
    var tip: CoachTip? = nil
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

    private func tipColor(for domain: String) -> Color {
        switch domain {
        case "nutrition": return .statusGreen
        case "training":  return .statusOrange
        case "recovery":  return .statusBlue
        case "sleep":     return .statusPurple
        default:          return .statusOrange
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
        if let alert {
            alertContent(alert)
        } else if let brief {
            coachContent(brief)
        }
    }

    @ViewBuilder
    private func alertContent(_ alert: ProactiveAlert) -> some View {
        let accentColor: Color = alert.severity == "warning" ? Color.forge : .statusBlue
        let alertIcon: String = {
            switch alert.type {
            case "nutrition": return "fork.knife.circle.fill"
            case "recovery":  return "heart.fill"
            case "training":  return "figure.strengthtraining.traditional"
            default:          return "bell.fill"
            }
        }()
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(accentColor.opacity(0.15)).frame(width: 36, height: 36)
                Image(systemName: alertIcon)
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(accentColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(alert.title)
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(.appTextPrimary)
                Text(alert.message)
                    .font(.appCaption)
                    .foregroundColor(Color.appOnSurface.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: { onDismissAlert?() }) {
                Image(systemName: "xmark")
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(.gray.opacity(0.7))
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .glassCardAccent(accentColor, cornerRadius: 14)
    }

    @ViewBuilder
    private func coachContent(_ brief: MorningBriefData) -> some View {
        Button {
            AppState.shared.pendingDeepLink = "intelligence"
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(Color.forge.opacity(0.18)).frame(width: 40, height: 40)
                    Image(systemName: "brain.head.profile")
                        .font(.appBody.weight(.semibold))
                        .foregroundColor(Color.forge)
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(contextLabel)
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(Color.forge)
                            .textCase(.uppercase)
                            .tracking(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.appCaption.weight(.medium))
                            .foregroundColor(Color.appOnSurface.opacity(0.35))
                    }
                    Text(brief.message)
                        .font(.appLabel.weight(.regular))
                        .foregroundColor(Color.appOnSurface.opacity(0.85))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                    if let tip {
                        Rectangle().fill(Color.appSurfaceInset).frame(height: 0.5).padding(.top, 4)
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: tipIcon(for: tip.domain))
                                .font(.appCaption)
                                .foregroundColor(tipColor(for: tip.domain))
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tip.title)
                                    .font(.appCaption.weight(.bold))
                                    .foregroundColor(Color.appOnSurface.opacity(0.9))
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
            .background(Color.forge.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.forge.opacity(0.22), lineWidth: 1))
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}
