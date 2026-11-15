import SwiftUI

// MARK: - BreathworkPracticeView

struct BreathworkPracticeView: View {
    @State private var techniquesState = Loadable<[BreathworkTechnique]>()
    @State private var historyState    = Loadable<[BreathworkSession]>()
    @State private var activeTechnique: BreathworkTechnique?

    private var techniques: [BreathworkTechnique] { techniquesState.value ?? [] }
    private var history:    [BreathworkSession]   { historyState.value    ?? [] }

    private var allStates: [any LoadableStateView] { [techniquesState, historyState] }
    private var topFailureAggregator: LoadableAggregator {
        LoadableAggregator(groups: [
            LoadableRetryGroup(states: allStates, retry: { await loadData() })
        ])
    }

    var body: some View {
        ZStack {
            AmbientBackground(color: Color.forge)

            if techniquesState.isInitialLoad && historyState.isInitialLoad {
                AppLoadingView()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        ErrorBannerView.fromAggregator(topFailureAggregator)
                            .padding(.horizontal, 16)

                        techniquesSection
                        historySection

                        Spacer(minLength: 32)
                    }
                    .padding(.vertical, 16)
                }
                .refreshable { await loadData() }
            }
        }
        .navigationTitle("Respiration")
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(item: $activeTechnique) { technique in
            BreathworkSessionView(technique: technique) {
                activeTechnique = nil
                Task { await reloadHistory() }
            }
        }
        .task { await loadData() }
    }

    // MARK: Sections

    private var techniquesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TECHNIQUES")
                .font(.appCaption.weight(.bold))
                .tracking(2).foregroundColor(.gray)
                .padding(.horizontal, 16)
            ForEach(techniques) { t in
                Button { activeTechnique = t } label: {
                    techniqueRow(t)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            }
        }
    }

    private func techniqueRow(_ t: BreathworkTechnique) -> some View {
        HStack(spacing: 14) {
            Image(systemName: t.icon)
                .font(.title3.weight(.regular))
                .foregroundStyle(Color.forge)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(t.name)
                    .font(.appBody.weight(.semibold))
                    .foregroundColor(Color.appOnSurface)
                Text(t.description)
                    .font(.appCaption)
                    .foregroundColor(Color.appOnSurface.opacity(0.6))
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundColor(Color.appOnSurface.opacity(0.3))
        }
        .padding(14)
        .glassCard()
    }

    @ViewBuilder
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HISTORIQUE — 30 JOURS")
                .font(.appCaption.weight(.bold))
                .tracking(2).foregroundColor(.gray)
                .padding(.horizontal, 16)

            if history.isEmpty && !historyState.isLoading {
                Text("Aucune séance sur les 30 derniers jours.")
                    .font(.appCaption)
                    .foregroundColor(Color.appOnSurface.opacity(0.6))
                    .padding(.horizontal, 16)
            } else {
                ForEach(history) { s in
                    historyRow(s).padding(.horizontal, 16)
                }
            }
        }
    }

    private func historyRow(_ s: BreathworkSession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.technique)
                    .font(.appBody.weight(.semibold))
                    .foregroundColor(Color.appOnSurface)
                Text(s.date)
                    .font(.appCaption)
                    .foregroundColor(Color.appOnSurface.opacity(0.5))
            }
            Spacer()
            Text("\(s.durationSec / 60)m\(String(format: "%02d", s.durationSec % 60))s · \(s.cycles) cycles")
                .font(.appCaption.monospacedDigit())
                .foregroundColor(Color.appOnSurface.opacity(0.6))
        }
        .padding(.vertical, 8)
    }

    // MARK: Loads

    private func loadData() async {
        let api = APIService.shared
        let tSeed = api.cachedSeed(for: APIService.breathworkTechniquesCacheKey, as: [BreathworkTechnique].self)
        let hSeed = api.cachedSeed(for: APIService.breathworkHistoryCacheKey(days: 30), as: [BreathworkSession].self)

        async let tLoad: Void = techniquesState.load(seed: tSeed.0, savedAt: tSeed.1) {
            try await api.fetchBreathworkTechniques(forceRefresh: true)
        }
        async let hLoad: Void = historyState.load(seed: hSeed.0, savedAt: hSeed.1) {
            try await api.fetchBreathworkHistory(days: 30, forceRefresh: true)
        }
        _ = await tLoad
        _ = await hLoad
    }

    private func reloadHistory() async {
        let api = APIService.shared
        let seed = api.cachedSeed(for: APIService.breathworkHistoryCacheKey(days: 30), as: [BreathworkSession].self)
        await historyState.load(seed: seed.0, savedAt: seed.1) {
            try await api.fetchBreathworkHistory(days: 30, forceRefresh: true)
        }
    }
}

// MARK: - BreathworkSessionView (full-screen guided practice)

private struct BreathworkSessionView: View {
    let technique: BreathworkTechnique
    let onDone: () -> Void

    @State private var startedAt   = Date()
    @State private var isRunning   = false
    @State private var isFinishing = false
    @State private var phaseIdx    = 0
    @State private var phaseElapsed: Double = 0  // secondes écoulées dans la phase courante
    @State private var cyclesDone  = 0
    @State private var submitError: String?
    @State private var timer: Timer?

    private var currentPhase: BreathworkPhase? {
        technique.phases.indices.contains(phaseIdx) ? technique.phases[phaseIdx] : nil
    }

    private var phaseDuration: Double {
        Double(currentPhase?.seconds ?? 1)
    }

    private var phaseProgress: Double {
        min(max(phaseElapsed / phaseDuration, 0), 1)
    }

    private var circleScale: CGFloat {
        guard let phase = currentPhase else { return 0.6 }
        switch phase.phase {
        case "inhale":                return 0.6 + CGFloat(phaseProgress) * 0.4
        case "exhale":                return 1.0 - CGFloat(phaseProgress) * 0.4
        case "hold":                  return 1.0
        case "holdOut":               return 0.6
        default:                      return 0.8
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                Text(technique.name)
                    .font(.appCaption.weight(.bold))
                    .tracking(3)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.top, 40)

                Spacer()

                Circle()
                    .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                    .background(Circle().fill(Color.white.opacity(0.06)))
                    .frame(width: 220, height: 220)
                    .scaleEffect(circleScale)
                    .animation(.linear(duration: 0.1), value: circleScale)

                VStack(spacing: 10) {
                    Text(isRunning ? (currentPhase?.label ?? "") : "Prêt")
                        .font(.title2.weight(.light))
                        .foregroundColor(.white)
                    Text("\(cyclesDone) / \(technique.targetCycles) cycles")
                        .font(.appCaption.monospacedDigit())
                        .foregroundColor(.white.opacity(0.5))
                }

                Spacer()

                if let err = submitError {
                    Text(err).font(.appCaption).foregroundColor(.red).padding(.horizontal)
                }

                HStack(spacing: 16) {
                    if !isRunning {
                        Button("Commencer") { start() }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.forge)
                            .disabled(isFinishing)
                    } else {
                        Button("Terminer") { Task { await finish() } }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.forge)
                            .disabled(isFinishing)
                    }
                    Button("Annuler") { stopTimer(); onDone() }
                        .buttonStyle(.bordered)
                        .tint(.white)
                        .disabled(isFinishing)
                }
                .padding(.bottom, 40)
            }
        }
        .onDisappear { stopTimer() }
    }

    // MARK: Lifecycle

    private func start() {
        startedAt   = Date()
        isRunning   = true
        phaseIdx    = 0
        phaseElapsed = 0
        cyclesDone  = 0
        submitError = nil
        startTimer()
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in advance(by: 0.1) }
        }
    }

    private func stopTimer() { timer?.invalidate(); timer = nil }

    private func advance(by dt: Double) {
        phaseElapsed += dt
        if phaseElapsed >= phaseDuration {
            phaseElapsed = 0
            if let phase = currentPhase, phase.phase == "exhale" || (phase.phase == "holdOut") {
                // Un cycle est complété à la fin de l'expiration (ou de holdOut si présent).
                let isLastPhase = phaseIdx == technique.phases.count - 1
                if isLastPhase { cyclesDone += 1 }
            }
            phaseIdx = (phaseIdx + 1) % technique.phases.count
        }
    }

    private func finish() async {
        stopTimer()
        isFinishing = true
        submitError = nil
        let elapsedSec = max(Int(Date().timeIntervalSince(startedAt)), 0)
        do {
            _ = try await APIService.shared.submitBreathworkSession(
                techniqueId: technique.id,
                durationSec: elapsedSec,
                cycles:      cyclesDone,
                startedAt:   startedAt
            )
            onDone()
        } catch {
            submitError = "Erreur enregistrement : \(error.localizedDescription)"
            isFinishing = false
        }
    }
}
