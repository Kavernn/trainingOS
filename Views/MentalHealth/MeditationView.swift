import SwiftUI
import AudioToolbox

// MARK: - MeditationView (réglage + historique)
// Recréé depuis bb765893^:Views/Spirit/SpiritMeditationView.swift (mêmes durées,
// même cloche, même minuteur). Différences voulues : started_at envoyé par le
// client, envoi hors de la Task du minuteur, erreurs visibles, historique Loadable.

struct MeditationView: View {
    @State private var durationMin  = 10
    @State private var bellInterval = 0   // 0 = aucune, sinon secondes
    @State private var showSession  = false
    @State private var historyState = Loadable<[MeditationSession]>()

    private let durations   = [5, 10, 15, 20, 30]
    private let bellOptions = [(0, "—"), (300, "5 min"), (600, "10 min"), (900, "15 min")]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                setupSection
                historySection
                    .padding(.top, 40)
                Spacer(minLength: 32)
            }
            .padding(.vertical, 24)
        }
        .background(Color.voidBg.ignoresSafeArea())
        .navigationTitle("Méditation")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await loadHistory() }
        .fullScreenCover(isPresented: $showSession, onDismiss: { Task { await loadHistory() } }) {
            MeditationSessionView(plannedSec: durationMin * 60, bellInterval: bellInterval)
        }
        .task { await loadHistory() }
    }

    // MARK: Réglage

    private var setupSection: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("\(durationMin)")
                    .font(.system(size: 80, weight: .ultraLight, design: .monospaced))
                    .foregroundStyle(Color.moonlight.opacity(0.75))
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: durationMin)
                Text("minutes")
                    .font(.appLabel.weight(.ultraLight))
                    .foregroundStyle(Color.moonlight.opacity(0.3))
            }

            HStack(spacing: 0) {
                ForEach(durations, id: \.self) { d in
                    Button { durationMin = d } label: {
                        Text("\(d)")
                            .font(.system(size: 13, weight: d == durationMin ? .regular : .ultraLight, design: .monospaced))
                            .foregroundStyle(d == durationMin ? Color.moonlight.opacity(0.8) : Color.moonlight.opacity(0.2))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                }
            }
            .padding(.top, 24)

            VStack(spacing: 8) {
                Text("CLOCHE")
                    .font(.system(size: 9, weight: .ultraLight, design: .monospaced))
                    .foregroundStyle(Color.moonlight.opacity(0.2))
                    .tracking(3)
                HStack(spacing: 0) {
                    ForEach(bellOptions, id: \.0) { sec, label in
                        Button { bellInterval = sec } label: {
                            Text(label)
                                .font(.system(size: 12, weight: sec == bellInterval ? .regular : .ultraLight))
                                .foregroundStyle(sec == bellInterval ? Color.moonlight.opacity(0.7) : Color.moonlight.opacity(0.2))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
            .padding(.top, 32)

            Button { showSession = true } label: {
                Image(systemName: "play.circle")
                    .font(.system(size: 44, weight: .ultraLight))
                    .foregroundStyle(Color.moonlight.opacity(0.35))
            }
            .padding(.top, 40)
        }
        .padding(.horizontal, 16)
    }

    // MARK: Historique

    @ViewBuilder
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RÉCENT")
                .font(.system(size: 9, weight: .ultraLight, design: .monospaced))
                .foregroundStyle(Color.moonlight.opacity(0.3))
                .tracking(3)

            SectionErrorView(state: historyState) { await loadHistory() }

            if historyState.isInitialLoad {
                ProgressView().tint(Color.moonlight.opacity(0.4))
            } else if let sessions = historyState.value {
                if sessions.isEmpty {
                    Text("Aucune séance de méditation.")
                        .font(.appCaption)
                        .foregroundStyle(Color.moonlight.opacity(0.4))
                } else {
                    ForEach(sessions) { s in historyRow(s) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    private func historyRow(_ s: MeditationSession) -> some View {
        HStack {
            Text(Self.displayDate(s.startedAt))
                .font(.system(size: 12, weight: .light, design: .monospaced))
                .foregroundStyle(Color.moonlight.opacity(0.55))
            Spacer()
            Text("\(s.actualSec / 60) / \(s.plannedSec / 60) min")
                .font(.system(size: 12, weight: .light, design: .monospaced))
                .foregroundStyle(Color.moonlight.opacity(0.55))
            Image(systemName: s.completed ? "checkmark.circle" : "xmark.circle")
                .font(.system(size: 12, weight: .light))
                .foregroundStyle(Color.moonlight.opacity(s.completed ? 0.6 : 0.25))
        }
        .padding(.vertical, 6)
    }

    private func loadHistory() async {
        let api  = APIService.shared
        let seed = api.cachedSeed(for: APIService.meditationHistoryCacheKey, as: [MeditationSession].self)
        await historyState.load(seed: seed.0, savedAt: seed.1) {
            try await api.fetchMeditationHistory(forceRefresh: true)
        }
    }

    /// started_at Postgres peut porter des fractions de seconde (ligne du 2026-05-29, DEFAULT now()).
    private static func displayDate(_ iso: String) -> String {
        let plain = ISO8601DateFormatter()
        let frac  = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = plain.date(from: iso) ?? frac.date(from: iso) else { return iso }  // brut, jamais masqué
        let f = DateFormatter()
        f.locale     = Locale(identifier: "fr_CA")
        f.timeZone   = TimeZone(identifier: "America/Montreal") ?? .current
        f.dateFormat = "d MMM · HH:mm"
        return f.string(from: date)
    }
}

// MARK: - Séance active

struct MeditationSessionView: View {
    let plannedSec: Int
    let bellInterval: Int

    @Environment(\.dismiss) private var dismiss

    private enum SendState: Equatable {
        case idle, sending, saved, queuedOffline
        case failed(String)
    }

    @State private var elapsed      = 0
    @State private var isRunning    = false
    @State private var isFinished   = false
    @State private var showControls = true
    @State private var startedAt    = Date()
    @State private var completed    = false
    @State private var actualSec    = 0
    @State private var sendState: SendState = .idle
    @State private var timerTask: Task<Void, Never>?
    @State private var controlHideTask: Task<Void, Never>?

    private var remaining: Int { max(0, plannedSec - elapsed) }

    var body: some View {
        ZStack {
            Color.voidBg.ignoresSafeArea()

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { revealControls() }

            VStack {
                Spacer()
                Text(formatTime(isFinished ? elapsed : remaining))
                    .font(.system(size: 64, weight: .ultraLight, design: .monospaced))
                    .foregroundStyle(Color.moonlight.opacity(isFinished ? 0.6 : 0.55))
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.easeInOut(duration: 0.3), value: remaining)
                Spacer()
                if showControls || !isRunning {
                    controlsView.transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.4), value: showControls)
        .onAppear { startSession() }
        .onDisappear {
            controlHideTask?.cancel()
            // Sortie imprévue pendant la séance → abandon, envoyé comme tel.
            if isRunning { stopSession() }
        }
    }

    @ViewBuilder
    private var controlsView: some View {
        VStack(spacing: 20) {
            if isFinished {
                VStack(spacing: 12) {
                    Text(completed ? "Bien." : "Séance interrompue.")
                        .font(.system(size: 20, weight: .ultraLight))
                        .foregroundStyle(Color.moonlight.opacity(0.55))
                    sendStatusView
                    Button("Fermer") { dismiss() }
                        .font(.appLabel.weight(.ultraLight))
                        .foregroundStyle(Color.moonlight.opacity(0.3))
                        .disabled(sendState == .sending)
                }
            } else if isRunning {
                Button("Terminer") { stopSession() }
                    .font(.appLabel.weight(.ultraLight))
                    .foregroundStyle(Color.moonlight.opacity(0.25))
            }
        }
        .padding(.bottom, 60)
    }

    @ViewBuilder
    private var sendStatusView: some View {
        switch sendState {
        case .idle, .sending:
            ProgressView().tint(Color.moonlight.opacity(0.4))
        case .saved:
            Text("Enregistrée")
                .font(.appCaption).foregroundStyle(Color.moonlight.opacity(0.4))
        case .queuedOffline:
            Text("Hors ligne — sera envoyée à la reconnexion.")
                .font(.appCaption).foregroundStyle(Color.appWarning)
        case .failed(let msg):
            VStack(spacing: 8) {
                Text("Séance non enregistrée : \(msg)")
                    .font(.appCaption).foregroundStyle(Color.appDanger)
                    .multilineTextAlignment(.center)
                // Même started_at → idempotent côté serveur (migration 106).
                Button("Réessayer") { launchSend() }
                    .font(.appLabel.weight(.light))
                    .foregroundStyle(Color.moonlight.opacity(0.6))
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: Minuteur (Swift pur, aucun réseau)

    private func startSession() {
        guard !isRunning && !isFinished else { return }
        isRunning = true
        startedAt = Date()   // clé d'idempotence, capturée au lancement
        elapsed   = 0
        autoHideControls()

        timerTask = Task { @MainActor in
            while elapsed < plannedSec {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return   // annulée par stopSession(), qui finalise elle-même
                }
                elapsed += 1
                if bellInterval > 0 && elapsed % bellInterval == 0 && elapsed < plannedSec {
                    AudioServicesPlaySystemSound(1013)
                }
            }
            finish(completed: true)
        }
    }

    /// Abandon (bouton « Terminer » ou sortie imprévue).
    private func stopSession() {
        timerTask?.cancel()
        finish(completed: false)
    }

    private func finish(completed: Bool) {
        guard !isFinished else { return }   // un seul envoi par séance
        isRunning    = false
        isFinished   = true
        showControls = true
        controlHideTask?.cancel()
        self.completed = completed
        actualSec = Int(Date().timeIntervalSince(startedAt))
        AudioServicesPlaySystemSound(1013)
        UINotificationFeedbackGenerator().notificationOccurred(completed ? .success : .warning)
        launchSend()
    }

    // MARK: Envoi

    /// Task NEUVE et non structurée : n'hérite pas de l'annulation de timerTask
    /// (Task {} n'est pas un enfant). Précédent 0e : l'ancien écran envoyait dans
    /// la Task annulée → URLError.cancelled → mis en file par offlinePost.
    private func launchSend() {
        let payload = (planned: plannedSec, actual: actualSec, bell: bellInterval,
                       completed: completed, startedAt: startedAt)
        sendState = .sending
        Task { @MainActor in
            do {
                try await APIService.shared.submitMeditationSession(
                    plannedSec:   payload.planned,
                    actualSec:    payload.actual,
                    bellInterval: payload.bell,
                    completed:    payload.completed,
                    startedAt:    payload.startedAt
                )
                sendState = .saved
            } catch APIError.queuedOffline {
                sendState = .queuedOffline
            } catch {
                sendState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: Contrôles

    private func revealControls() {
        guard isRunning else { return }
        showControls = true
        autoHideControls()
    }

    private func autoHideControls() {
        controlHideTask?.cancel()
        controlHideTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 3_000_000_000)
            } catch {
                return   // annulée : un nouveau masquage a été programmé ou la séance est finie
            }
            showControls = false
        }
    }

    private func formatTime(_ sec: Int) -> String {
        String(format: "%d:%02d", sec / 60, sec % 60)
    }
}
