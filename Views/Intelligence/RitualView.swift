import SwiftUI

// Entry point — decides which ritual phase to show
struct RitualView: View {
    @State private var ritual: RitualToday? = nil
    @State private var isLoading = true
    @State private var showDemons = false
    @Environment(\.dismiss) private var dismiss

    private var phase: RitualPhase {
        guard let r = ritual else { return .loading }
        if !r.morningDone        { return .morning }
        if !r.eveningDone        { return .evening }
        return .done
    }

    var body: some View {
        ZStack {
            Color(hex: "0A0A0A").ignoresSafeArea()

            if isLoading {
                ProgressView().tint(Color(hex: "FF2D20"))
            } else if let r = ritual {
                switch phase {
                case .morning:
                    RitualMorningView(ritual: r) { updated in
                        ritual = updated
                    }
                case .evening:
                    RitualEveningView(ritual: r) { updated in
                        ritual = updated
                    }
                case .done:
                    RitualDoneView(ritual: r, onDemons: { showDemons = true })
                case .loading:
                    EmptyView()
                }
            } else {
                ritualUnavailableView
            }
        }
        .sheet(isPresented: $showDemons) {
            DemonsView(demons: ritual?.demons ?? [])
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
                .foregroundColor(Color(hex: "FF2D20"))
        }
    }

    private func load() async {
        isLoading = true
        ritual    = try? await APIService.shared.fetchRitualToday()
        // Always bypass cache for ritual — stale data breaks state machine
        CacheService.shared.clear(for: "ritual_today")
        isLoading = false
    }
}

private enum RitualPhase { case loading, morning, evening, done }

// ── Done state ───────────────────────────────────────────────────────────────

struct RitualDoneView: View {
    let ritual: RitualToday
    let onDemons: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                // Outcome badge
                if ritual.burnedToday {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 48))
                        .foregroundColor(Color(hex: "FF2D20"))
                } else {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                }

                Text(ritual.burnedToday ? "BURNED" : "SURVIVED")
                    .font(.system(size: 13, weight: .black))
                    .tracking(4)
                    .foregroundColor(ritual.burnedToday ? Color(hex: "FF2D20") : .gray)

                // Phoenix streak
                if ritual.phoenixStreak > 0 {
                    VStack(spacing: 6) {
                        Text("\(ritual.phoenixStreak)")
                            .font(.system(size: 64, weight: .black))
                            .foregroundColor(.white)
                        Text("JOURS CONSÉCUTIFS")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(3)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 8)
                }

                Text("\(ritual.phoenixTotalBurned) intentions tuées au total")
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: 0.4))
            }
            Spacer()

            // Demons link
            if !ritual.demons.isEmpty {
                Button(action: onDemons) {
                    HStack(spacing: 6) {
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 13))
                        Text("\(ritual.demons.count) démon\(ritual.demons.count > 1 ? "s" : "") en attente")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(Color(white: 0.35))
                }
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
