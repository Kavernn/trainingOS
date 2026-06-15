import SwiftUI

struct CoachMissionCard: View {
    let dash: DashboardData
    let onOpenSession: (() -> Void)?
    let onRefreshBrief: () -> Void

    private var sessionColor: Color {
        switch dash.today {
        case "Push A", "Push B":             return .statusOrange
        case "Pull A", "Pull B + Full Body": return .statusCyan
        case "Legs":                         return .statusYellow
        case "Yoga / Tai Chi":               return .statusPurple
        case "Recovery":                     return .statusGreen
        default:                             return .statusBlue
        }
    }

    private var sessionDone: Bool {
        dash.alreadyLoggedToday || dash.sessions[dash.todayDate] != nil
    }

    private var hasDraft: Bool {
        SessionDraftStore.hasAnyDraft(date: dash.todayDate)
    }

    private var ctaLabel: String {
        if sessionDone { return "Voir ma séance" }
        if hasDraft    { return "Reprendre la séance" }
        return "Commencer →"
    }

    private var ctaIcon: String {
        if sessionDone { return "checkmark.circle.fill" }
        if hasDraft    { return "play.fill" }
        return "bolt.fill"
    }

    private var statusLabel: String {
        if sessionDone { return "Terminé ✓" }
        if hasDraft    { return "En cours" }
        return "À faire"
    }

    private var statusColor: Color {
        if sessionDone { return .statusGreen }
        if hasDraft    { return .statusOrange }
        return sessionColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MISSION DU JOUR")
                        .font(.system(size: 10, weight: .black))
                        .tracking(2)
                        .foregroundColor(sessionColor)
                    Text(dash.today)
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(.appTextPrimary)
                }
                Spacer()
                Text(statusLabel)
                    .font(.appCaption.weight(.bold))
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(statusColor.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider().background(Color.appSeparator)

            HStack(spacing: 10) {
                Button(action: { onOpenSession?() }) {
                    HStack(spacing: 8) {
                        Image(systemName: ctaIcon)
                            .font(.system(size: 14, weight: .bold))
                        Text(ctaLabel)
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(sessionDone ? Color.appSuccess : sessionColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(ScaleButtonStyle())

                Button(action: onRefreshBrief) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.appOnSurface.opacity(0.3))
                        .frame(width: 38, height: 38)
                        .background(Color.appSurfaceInset)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(
            ZStack {
                Color.appBg
                LinearGradient(
                    colors: [sessionColor.opacity(0.12), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(sessionColor.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

private struct MissionShimmer: View {
    @State private var opacity: Double = 0.06

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.appOnSurface.opacity(opacity))
                    .frame(maxWidth: i == 3 ? 140 : .infinity)
                    .frame(height: 12)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                opacity = 0.16
            }
        }
    }
}
