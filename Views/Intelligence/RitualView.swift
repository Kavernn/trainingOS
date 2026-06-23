import SwiftUI

// Entry point — decides which ritual phase to show
struct RitualView: View {
    @State private var ritual: RitualToday? = nil
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    private var phase: RitualPhase {
        guard let r = ritual else { return .loading }
        // Adressage prioritaire si des engagements du jour sont en attente
        if r.hasEngagementsToday && !r.allEngagementsAddressed { return .addressing }
        // Création si demain n'est pas encore préparé
        if !r.tomorrowCreated { return .creating }
        return .done
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()

                if isLoading {
                    ProgressView().tint(Color.appDanger)
                } else if let r = ritual {
                    switch phase {
                    case .addressing:
                        EngagementAddressingView(ritual: r) { updated in
                            ritual = updated
                        }
                    case .creating:
                        EngagementCreationView(ritual: r) { updated in
                            ritual = updated
                            if updated.tomorrowCreated { ActionFeedbackManager.shared.show(.ritualComplete) }
                        }
                    case .done:
                        RitualDoneView(ritual: r)
                    case .loading:
                        EmptyView()
                    }
                } else {
                    ritualUnavailableView
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(white: 0.4))
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await load() }
    }

    private var ritualUnavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 32)).foregroundColor(.gray)
            Text("Indisponible — réessaie dans un instant")
                .font(.system(size: 14)).foregroundColor(.gray)
            Button("Réessayer") { Task { await load() } }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.appDanger)
        }
    }

    private func load() async {
        isLoading = true
        // Clear cache before fetching — stale data breaks the phase state machine
        CacheService.shared.clear(for: "ritual_today")
        ritual    = try? await APIService.shared.fetchRitualToday()
        isLoading = false
    }
}

private enum RitualPhase { case loading, addressing, creating, done }

// ── Done state ───────────────────────────────────────────────────────────────

struct RitualDoneView: View {
    let ritual: RitualToday

    private let amber = Color.appWarning

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Text(todayLabel)
                    .font(.appCaption)
                    .foregroundColor(Color(white: 0.25))
                    .tracking(1)
                    .padding(.top, 40)

                Spacer(minLength: 40)

                cycleStateBlock
                    .padding(.horizontal, 24)

                Spacer(minLength: 48)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var cycleStateBlock: some View {
        VStack(spacing: 16) {
            if ritual.tomorrowCreated {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(amber)
                Text("Cycle complété")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.appTextPrimary)
                Text(tomorrowEngagementsLabel)
                    .font(.appLabel)
                    .foregroundColor(Color(white: 0.35))
            } else {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 48))
                    .foregroundColor(Color(white: 0.3))
                Text("Journée clôturée")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.appTextPrimary)
                Text("Ce soir, crée tes engagements pour demain.")
                    .font(.appLabel)
                    .foregroundColor(Color(white: 0.35))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var tomorrowEngagementsLabel: String {
        let n = ritual.tomorrowEngagements.count
        return "\(n) engagement\(n > 1 ? "s" : "") prévus pour demain"
    }

    private var todayLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE d MMMM"
        fmt.locale = Locale(identifier: "fr_CA")
        return fmt.string(from: Date()).capitalized
    }
}

