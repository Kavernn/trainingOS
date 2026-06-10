import SwiftUI

// Écran B — Adressage des engagements créés la veille
struct EngagementAddressingView: View {
    let ritual: RitualToday
    let onSaved: (RitualToday) -> Void

    // id → statut local (reflète les taps immédiats avant la réponse serveur)
    @State private var localStatuses: [String: String] = [:]

    private let amber = Color.appWarning

    private func status(for e: RitualEngagement) -> String? {
        localStatuses[e.id] ?? e.status
    }

    private var allAddressed: Bool {
        ritual.engagements.allSatisfy { status(for: $0) != nil }
    }

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    headerBlock
                        .padding(.top, 40)
                        .padding(.horizontal, 24)

                    engagementList
                        .padding(.top, 24)

                    if allAddressed {
                        nextButton
                            .padding(.top, 28)
                            .padding(.horizontal, 24)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    Spacer(minLength: 80)
                }
                .animation(.easeInOut(duration: 0.25), value: allAddressed)
            }
        }
    }

    // MARK: - Header

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(todayLabel)
                .font(.system(size: 12))
                .foregroundColor(Color(white: 0.28))
                .tracking(0.5)

            Text("Tes engagements d'hier")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)

            if let ts = ritual.engagementsCreatedAt {
                Text(ts)
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.28))
            }
        }
    }

    // MARK: - List

    private var engagementList: some View {
        VStack(spacing: 10) {
            ForEach(ritual.engagements) { engagement in
                EngagementAddressRow(
                    text: engagement.text,
                    status: status(for: engagement),
                    onDone:    { address(engagement, status: "done") },
                    onNotDone: { address(engagement, status: "notdone") }
                )
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Next button

    private var nextButton: some View {
        Button(action: advance) {
            HStack(spacing: 8) {
                Text("Prépare demain")
                    .font(.appBody.weight(.semibold))
                    .foregroundColor(.black)
                Image(systemName: "arrow.right")
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(amber)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var todayLabel: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_CA")
        fmt.dateFormat = "EEEE d MMMM"
        return fmt.string(from: Date()).capitalized
    }

    private func address(_ engagement: RitualEngagement, status: String) {
        guard localStatuses[engagement.id] == nil,
              engagement.status == nil else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.2)) {
            localStatuses[engagement.id] = status
        }
        Task { try? await APIService.shared.updateEngagementStatus(id: engagement.id, status: status) }
    }

    private func advance() {
        Task {
            CacheService.shared.clear(for: "ritual_today")
            if let updated = try? await APIService.shared.fetchRitualToday() {
                await MainActor.run { onSaved(updated) }
            }
        }
    }
}

// MARK: - Engagement Address Row

private struct EngagementAddressRow: View {
    let text: String
    let status: String?
    let onDone: () -> Void
    let onNotDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, status == nil ? 12 : 16)

            if status == nil {
                Rectangle()
                    .fill(Color(white: 0.1))
                    .frame(height: 1)
                    .padding(.horizontal, 16)

                HStack(spacing: 0) {
                    actionButton(label: "Fait  ✓", color: Color.appSuccess, action: onDone)
                    Rectangle().fill(Color(white: 0.1)).frame(width: 1, height: 36)
                    actionButton(label: "Pas fait  ✗", color: Color(white: 0.38), action: onNotDone)
                }
            }
        }
        .background(rowBackground)
        .cornerRadius(12)
    }

    private func actionButton(label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.appLabel.weight(.semibold))
                .foregroundColor(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private var textColor: Color {
        switch status {
        case "done":    return Color.appSuccess
        case "notdone": return Color(white: 0.32)
        default:        return .white
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(fillColor)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(strokeColor, lineWidth: 1))
    }

    private var fillColor: Color {
        switch status {
        case "done":    return Color(hex: "1C3B2A")
        case "notdone": return Color(hex: "1A0A0A")
        default:        return Color(white: 0.07)
        }
    }

    private var strokeColor: Color {
        switch status {
        case "done":    return Color.appSuccess.opacity(0.3)
        default:        return Color(white: 0.1)
        }
    }
}
