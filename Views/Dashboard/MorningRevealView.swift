import SwiftUI

// MARK: - Morning Reveal View
// Shown once per day on first app open before 14h.
// Flow : check-in (4 sliders) → save → refetch brief → révélation du verdict.
// L'enqueue ne dépend plus du brief (DashboardView:checkAndShowMorningReveal) ;
// la vue fetch le brief elle-même après le check-in.
struct MorningRevealView: View {
    let onDismiss: () -> Void

    private enum Phase: Equatable {
        case loading           // bootstrap: fetch recovery pour décider check-in
        case checkIn           // sliders affichés, user interagit
        case loadingReveal     // save (optionnel) + fetch brief en cours
        case reveal            // morningBrief chargé, animation
        case briefError        // fetch brief a échoué
    }

    @State private var phase: Phase = .loading
    @State private var morningBrief: MorningBriefData? = nil

    // Check-in state
    @State private var sleepQuality: Double = 0
    @State private var fatigue: Double = 0
    @State private var soreness: Double = 0
    @State private var energyPre: Double = 0

    // Flow flags
    @State private var isSubmitting = false
    @State private var checkInError: String? = nil
    @State private var noServerRecompute = false     // save queued offline → verdict pas recalculé serveur
    @State private var briefErrorMessage: String? = nil

    // Reveal animation state
    @State private var showReveal = false
    @State private var showDetails = false
    @State private var showButton = false
    @State private var pulse = false
    @State private var breathe = false

    private var todayStr: String { AppState.shared.todayStr }

    private var accentColor: Color {
        switch morningBrief?.recommendation {
        case "go":         return .statusGreen
        case "go_caution": return .appWarning
        case "reduce":     return .statusOrange
        default:           return .statusRed
        }
    }

    private var icon: String {
        switch morningBrief?.recommendation {
        case "go":         return "bolt.fill"
        case "go_caution": return "tortoise.fill"
        case "reduce":     return "arrow.down.circle.fill"
        default:           return "moon.zzz.fill"
        }
    }

    private var title: String {
        switch morningBrief?.recommendation {
        case "go":         return "Journée optimale"
        case "go_caution": return "Forme correcte"
        case "reduce":     return "Intensité réduite"
        default:           return "Journée de repos"
        }
    }

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            switch phase {
            case .loading:
                loadingView(label: "Chargement…")
            case .checkIn:
                checkInView
            case .loadingReveal:
                loadingView(label: "Lecture du terrain…")
            case .reveal:
                revealView
            case .briefError:
                briefErrorView
            }
        }
        .preferredColorScheme(.dark)
        .task { await bootstrap() }
    }

    // MARK: - Phases

    @ViewBuilder
    private func loadingView(label: String) -> some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(Color.appOnSurface.opacity(0.4))
                .scaleEffect(1.1)
            Text(label)
                .font(.appLabel)
                .foregroundColor(Color.appOnSurface.opacity(0.35))
        }
    }

    @ViewBuilder
    private var checkInView: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("CHECK-IN DU MATIN")
                        .font(.appCaption.weight(.black))
                        .tracking(3)
                        .foregroundColor(Color.forge.opacity(0.9))
                    Text("Comment tu te sens ?")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                    Text("Tes réponses ajustent le verdict du jour.")
                        .font(.appLabel)
                        .foregroundColor(Color.appOnSurface.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)
                .padding(.horizontal, 24)

                MorningCheckInBlock(sleepQuality: $sleepQuality,
                                    fatigue: $fatigue,
                                    soreness: $soreness,
                                    energyPre: $energyPre)
                .padding(.horizontal, 20)

                if let err = checkInError {
                    Text(err)
                        .font(.appCaption)
                        .foregroundColor(Color.statusRed)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                VStack(spacing: 10) {
                    Button(action: submitAndReveal) {
                        HStack {
                            if isSubmitting { ProgressView().tint(.appBg).scaleEffect(0.9) }
                            Text(isSubmitting ? "Enregistrement…" : "Valider mon check-in")
                                .font(.appBody.weight(.bold))
                                .foregroundColor(Color.appBg)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.forge)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(SpringButtonStyle())
                    .disabled(isSubmitting)

                    Button(action: skipAndReveal) {
                        Text("Passer")
                            .font(.appLabel.weight(.semibold))
                            .foregroundColor(Color.appOnSurface.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
    }

    @ViewBuilder
    private var revealView: some View {
        // Respiration forge
        RadialGradient(
            colors: [Color.forge.opacity(breathe && !showReveal ? 0.12 : 0), Color.clear],
            center: .center, startRadius: 0, endRadius: 300
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 2.4), value: breathe)

        RadialGradient(
            colors: [accentColor.opacity(showReveal ? 0.18 : 0), Color.clear],
            center: .center, startRadius: 0, endRadius: 320
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.2), value: showReveal)

        VStack(spacing: 0) {
            Spacer()

            if noServerRecompute && showReveal {
                Text("Verdict calculé sans ton check-in du jour")
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(Color.statusYellow)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.statusYellow.opacity(0.1))
                    .overlay(Capsule().stroke(Color.statusYellow.opacity(0.3), lineWidth: 1))
                    .clipShape(Capsule())
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }

            if showReveal, let brief = morningBrief {
                VStack(spacing: 28) {
                    ZStack {
                        Circle()
                            .stroke(accentColor.opacity(0.15), lineWidth: 1)
                            .frame(width: 160, height: 160)
                            .scaleEffect(pulse ? 1.06 : 1)
                            .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: pulse)

                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [accentColor.opacity(0.22), accentColor.opacity(0.04)],
                                    center: .center, startRadius: 0, endRadius: 80
                                )
                            )
                            .frame(width: 140, height: 140)

                        Image(systemName: icon)
                            .font(.system(size: 56, weight: .bold))
                            .foregroundColor(accentColor)
                    }

                    VStack(spacing: 10) {
                        Text(title.uppercased())
                            .font(.appCaption.weight(.black))
                            .tracking(3)
                            .foregroundColor(accentColor.opacity(0.75))

                        Text(brief.sessionToday.isEmpty ? title : brief.sessionToday)
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundColor(.appTextPrimary)

                        Text(brief.message)
                            .font(.appLabel)
                            .foregroundColor(Color.appOnSurface.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, 36)
                    }
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.6).combined(with: .opacity),
                    removal: .opacity
                ))
            }

            Spacer().frame(height: 48)

            if showDetails, let brief = morningBrief {
                VStack(spacing: 20) {
                    if let components = brief.components {
                        RevealComponentsRow(components: components)
                    }
                    let activeFlags = activeFlagChips(for: brief)
                    if !activeFlags.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(activeFlags, id: \.text) { chip in
                                RevealFlagChip(icon: chip.icon, text: chip.text, color: chip.color)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer().frame(height: 32)

            if showButton {
                Button(action: onDismiss) {
                    Text("Partir au combat")
                        .font(.appBody.weight(.bold))
                        .foregroundColor(Color.appBg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(SpringButtonStyle())
                .padding(.horizontal, 32)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer().frame(height: 48)
        }
    }

    @ViewBuilder
    private var briefErrorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundColor(Color.statusOrange)
            Text("Impossible de charger le verdict")
                .font(.appHeadline)
                .foregroundColor(.appTextPrimary)
            if let msg = briefErrorMessage {
                Text(msg)
                    .font(.appLabel)
                    .foregroundColor(Color.appOnSurface.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            VStack(spacing: 10) {
                Button(action: { Task { await loadBrief() } }) {
                    Text("Réessayer")
                        .font(.appBody.weight(.bold))
                        .foregroundColor(Color.appBg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.forge)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(SpringButtonStyle())
                Button(action: onDismiss) {
                    Text("Fermer")
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(Color.appOnSurface.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
        }
    }

    // MARK: - Flow

    private func bootstrap() async {
        // Prefill from today's recovery entry if any ; décide check-in needed.
        let entries = (try? await APIService.shared.fetchRecoveryData()) ?? []
        if let today = entries.first(where: { $0.date == todayStr }) {
            sleepQuality = today.sleepQuality ?? 0
            fatigue      = today.fatigue     ?? 0
            soreness     = today.soreness    ?? 0
            energyPre    = today.energyPre   ?? 0
            if sleepQuality > 0 && fatigue > 0 && soreness > 0 && energyPre > 0 {
                await loadBrief()
                return
            }
        }
        phase = .checkIn
    }

    private func submitAndReveal() {
        isSubmitting = true
        checkInError = nil
        Task {
            do {
                let reachedServer = try await APIService.shared.logRecovery(
                    sleepHours:    nil,
                    sleepQuality:  sleepQuality > 0 ? sleepQuality : nil,
                    restingHr:     nil,
                    hrv:           nil,
                    steps:         nil,
                    soreness:      soreness == 0 ? nil : soreness,
                    fatigue:       fatigue == 0 ? nil : fatigue,
                    energyPre:     energyPre == 0 ? nil : energyPre,
                    activeEnergy:  nil, hrMorning: nil, hrPostWorkout: nil, hrEvening: nil,
                    notes:         nil,
                    date:          todayStr,
                    bedtime:       nil, wakeTime: nil
                )
                isSubmitting = false
                // Si queue offline : serveur n'a pas recalculé readiness/brief.
                noServerRecompute = !reachedServer
                await loadBrief()
            } catch {
                isSubmitting = false
                checkInError = "Enregistrement échoué — réessaie ou appuie sur Passer."
            }
        }
    }

    private func skipAndReveal() {
        noServerRecompute = false
        Task { await loadBrief() }
    }

    private func loadBrief() async {
        phase = .loadingReveal
        do {
            let brief = try await APIService.shared.fetchMorningBrief()
            morningBrief = brief
            phase = .reveal
            runRevealSequence()
        } catch {
            briefErrorMessage = "Vérifie ta connexion puis réessaie."
            phase = .briefError
        }
    }

    // MARK: - Reveal animation

    private func activeFlagChips(for brief: MorningBriefData) -> [(icon: String, text: String, color: Color)] {
        var chips: [(icon: String, text: String, color: Color)] = []
        if brief.flags.sleepDeprivation {
            chips.append((icon: "moon.zzz.fill", text: "Manque de sommeil", color: .statusBlue))
        }
        if brief.flags.hrvDrop {
            chips.append((icon: "waveform.path.ecg", text: "HRV en baisse", color: Color.forge))
        }
        if brief.flags.trainingOverload {
            chips.append((icon: "flame.fill", text: "Surcharge", color: .statusRed))
        }
        return chips
    }

    private func runRevealSequence() {
        Task { @MainActor in
            withAnimation(.easeInOut(duration: 2.4)) { breathe = true }
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            withAnimation(.easeInOut(duration: 0.6)) { breathe = false }
            withAnimation(.spring(response: 0.65, dampingFraction: 0.72)) { showReveal = true }
            pulse = true
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            withAnimation(.easeOut(duration: 0.45)) { showDetails = true }
            try? await Task.sleep(nanoseconds: 700_000_000)
            withAnimation(.easeOut(duration: 0.35)) { showButton = true }
        }
    }
}

// MARK: - Component chips row
private struct RevealComponentsRow: View {
    let components: MorningBriefComponents

    var body: some View {
        HStack(spacing: 10) {
            if let v = components.sleepQuality {
                RevealComponentChip(icon: "moon.fill", label: "Sommeil", quality: v, color: v > 0.6 ? .statusBlue : Color.forge)
            }
            if let v = components.hrvTrend {
                RevealComponentChip(icon: "waveform.path.ecg", label: "HRV", quality: v, color: v > 0.6 ? .statusGreen : .statusOrange)
            }
            if let v = components.rhrTrend {
                RevealComponentChip(icon: "heart.fill", label: "FC repos", quality: v, color: v > 0.6 ? .statusGreen : .statusRed)
            }
            if let v = components.trainingFatigue {
                RevealComponentChip(icon: "flame.fill", label: "Fatigue", quality: v, color: v > 0.6 ? .statusGreen : .statusOrange)
            }
        }
    }
}

private struct RevealComponentChip: View {
    let icon: String
    let label: String
    let quality: Double
    let color: Color

    private var qualityLabel: String {
        switch quality {
        case 0.8...: return "Excellent"
        case 0.6..<0.8: return "Bon"
        case 0.4..<0.6: return "Moyen"
        default: return "Faible"
        }
    }

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.appBody)
                .foregroundColor(color)
            Text(qualityLabel)
                .font(.appCaption.weight(.bold))
                .foregroundColor(.appTextPrimary)
            Text(label)
                .font(.appMicro.weight(.medium))
                .foregroundColor(Color.appOnSurface.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.18), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct RevealFlagChip: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.appCaption)
            Text(text).font(.appCaption.weight(.semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.10))
        .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 1))
        .clipShape(Capsule())
    }
}
