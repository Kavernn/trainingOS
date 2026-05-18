import SwiftUI

struct RitualEveningView: View {
    let ritual: RitualToday
    let onSaved: (RitualToday) -> Void

    @State private var selectedOutcome: String? = nil
    @State private var isSaving        = false
    @State private var showResult      = false
    @State private var result: RitualEveningResult? = nil
    @State private var flashOpacity: Double = 0

    private let red = Color(hex: "FF2D20")

    var body: some View {
        ZStack {
            Color(hex: "0A0A0A").ignoresSafeArea()

            // Red flash overlay for "burned" celebration
            Color(hex: "FF2D20")
                .ignoresSafeArea()
                .opacity(flashOpacity)
                .allowsHitTesting(false)

            if showResult, let r = result {
                resultView(r)
                    .transition(.opacity)
            } else {
                choiceView
            }
        }
        .animation(.easeInOut(duration: 0.4), value: showResult)
    }

    // MARK: - Choice view

    private var choiceView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CE MATIN TU AVAIS DIT")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(3)
                        .foregroundColor(Color(white: 0.28))

                    Text("«\u{202F}\(ritual.intention ?? "")\u{202F}»")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("— \(ritual.truth)")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.28))
                        .padding(.top, 2)
                }

                // Silence separator
                Rectangle()
                    .fill(Color(white: 0.08))
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 20) {
                    Text("EST-CE QUE TU L'AS TUÉ ?")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(3)
                        .foregroundColor(Color(white: 0.28))

                    HStack(spacing: 12) {
                        choiceButton(emoji: "🔥", label: "BURNED\nIT", outcome: "burned")
                        choiceButton(emoji: "💀", label: "SURVIVED", outcome: "survived")
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private func choiceButton(emoji: String, label: String, outcome: String) -> some View {
        let isSelected = selectedOutcome == outcome
        return Button(action: { commit(outcome: outcome) }) {
            VStack(spacing: 10) {
                Text(emoji).font(.system(size: 40))
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundColor(isSelected ? .white : Color(white: 0.45))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(Color(white: isSelected ? 0.12 : 0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color(white: 0.3) : Color(white: 0.1), lineWidth: 1)
            )
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    // MARK: - Result view

    private func resultView(_ r: RitualEveningResult) -> some View {
        VStack(spacing: 0) {
            Spacer()
            if r.outcome == "burned" {
                burnedResultContent(r)
            } else {
                survivedResultContent
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    private func burnedResultContent(_ r: RitualEveningResult) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "flame.fill")
                .font(.system(size: 48))
                .foregroundColor(red)

            VStack(spacing: 6) {
                Text("\(r.phoenixStreak)")
                    .font(.system(size: 72, weight: .black))
                    .foregroundColor(.white)
                Text("PHOENIX STREAK")
                    .font(.system(size: 12, weight: .black))
                    .tracking(4)
                    .foregroundColor(Color(white: 0.3))
            }

            // Animated streak bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(white: 0.08)).frame(height: 3)
                    Capsule()
                        .fill(red)
                        .frame(width: geo.size.width, height: 3)
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading),
                            removal: .opacity
                        ))
                }
            }
            .frame(height: 3)

            Text("\(r.phoenixTotalBurned) intentions tuées au total")
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.28))
        }
    }

    private var survivedResultContent: some View {
        VStack(spacing: 20) {
            Text("It's still there.")
                .font(.system(size: 26, weight: .light))
                .foregroundColor(.white)
            Text("Tomorrow you go again.")
                .font(.system(size: 14))
                .foregroundColor(Color(white: 0.3))
        }
    }

    // MARK: - Commit

    private func commit(outcome: String) {
        guard !isSaving else { return }
        selectedOutcome = outcome
        isSaving        = true

        Task {
            do {
                let r = try await APIService.shared.saveRitualEvening(outcome: outcome)
                await showEveningResult(r, outcome: outcome)
            } catch APIError.queuedOffline {
                // Queued — show a synthetic result so the user isn't left hanging
                let synthetic = RitualEveningResult(
                    ok: true, outcome: outcome,
                    phoenixStreak: 0, phoenixBest: 0, phoenixTotalBurned: 0
                )
                await showEveningResult(synthetic, outcome: outcome)
            } catch {
                await MainActor.run {
                    selectedOutcome = nil
                    isSaving        = false
                }
            }
        }
    }

    private func showEveningResult(_ r: RitualEveningResult, outcome: String) async {
        if outcome == "burned" {
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.15)) { flashOpacity = 0.6 }
            }
            try? await Task.sleep(nanoseconds: 180_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.35)) { flashOpacity = 0 }
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        await MainActor.run {
            result     = r
            showResult = true
            isSaving   = false
        }
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        if let updated = try? await APIService.shared.fetchRitualToday() {
            await MainActor.run { onSaved(updated) }
        }
    }
}
