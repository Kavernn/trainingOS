import SwiftUI

struct SeasonStartView: View {
    let seasonNumber: Int
    let onStarted: () -> Void
    let onDismiss: () -> Void

    @State private var phase: StartPhase = .intro
    @State private var isStarting = false
    @State private var startError: String?
    @State private var isQueued = false

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()
            switch phase {
            case .intro:  introView
            case .started: startedView
            }
        }
        .animation(.easeInOut(duration: 0.5), value: phase)
        .preferredColorScheme(.dark)
    }

    // MARK: - Intro

    private var introView: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 40) {
                VStack(spacing: 12) {
                    Text("SEASON \(seasonNumber)")
                        .font(.system(size: 36, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.primary)
                        .tracking(4)
                    Text("Aujourd'hui, tu tournes la page.")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(Color.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    trackingRow("scalemass.fill",   "Composition corporelle")
                    trackingRow("bird.fill",         "Phoenix Score")
                    trackingRow("shield.fill",       "War Room & streak")
                    trackingRow("dumbbell.fill",     "Personal records")
                    trackingRow("flame.fill",        "Rituels & habitudes")
                }
                .padding(.horizontal, 40)
            }

            Spacer()

            VStack(spacing: 6) {
                if isQueued {
                    Text("Démarrage en attente — hors ligne")
                        .font(.appCaption)
                        .foregroundColor(.appTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let msg = startError {
                    Text(msg)
                        .font(.appCaption)
                        .foregroundColor(.appDanger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Pas maintenant") { onDismiss() }
                        .font(.system(size: 14))
                        .foregroundStyle(Color.secondary)
                    Spacer()
                    Button {
                        Task { await startSeason() }
                    } label: {
                        if isStarting {
                            ProgressView().tint(.onAccent)
                        } else {
                            Text("Commencer")
                                .font(.appBody.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 12)
                                .background(Color.forge, in: Capsule())
                        }
                    }
                    .disabled(isStarting || isQueued)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 52)
        }
    }

    private func trackingRow(_ icon: String, _ label: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.forge.opacity(0.8))
                .frame(width: 20)
            Text(label)
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(Color.primary)
        }
    }

    // MARK: - Started

    private var startedView: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "flag.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.forge)
            VStack(spacing: 8) {
                Text("SEASON \(seasonNumber) EST LANCÉE")
                    .font(.system(size: 18, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.primary)
                    .tracking(2)
                Text("Le chrono tourne.")
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(Color.secondary)
            }
            Spacer()
            Button("Allons-y") { onStarted() }
                .font(.appBody.weight(.semibold))
                .foregroundStyle(Color.forge)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(Color.forge.opacity(0.12), in: Capsule())
                .padding(.bottom, 52)
        }
    }

    private func startSeason() async {
        isStarting = true
        startError = nil
        isQueued = false
        defer { Task { @MainActor in isStarting = false } }
        do {
            _ = try await APIService.shared.startSeason()
            // Succès serveur UNIQUEMENT : passage à la phase "started".
            await MainActor.run { withAnimation { phase = .started } }
        } catch APIError.queuedOffline {
            await MainActor.run { isQueued = true }
        } catch APIError.serverError(_, let msg) {
            await MainActor.run { startError = msg.isEmpty ? "Erreur serveur" : msg }
        } catch {
            await MainActor.run { startError = "Erreur réseau — réessaie" }
        }
    }
}

private enum StartPhase { case intro, started }
