import SwiftUI
import AudioToolbox

// MARK: - Setup tab

struct SpiritMeditationTabView: View {
    @ObservedObject var vm: SpiritViewModel
    @State private var durationMin  = 10
    @State private var bellInterval = 0   // 0 = none, 300 = 5min, 600 = 10min, 900 = 15min
    @State private var showSession  = false

    private let durations    = [5, 10, 15, 20, 30]
    private let bellOptions  = [(0, "—"), (300, "5 min"), (600, "10 min"), (900, "15 min")]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Duration picker
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

            // Duration selector
            HStack(spacing: 0) {
                ForEach(durations, id: \.self) { d in
                    Button {
                        durationMin = d
                    } label: {
                        Text("\(d)")
                            .font(.system(size: 13, weight: d == durationMin ? .regular : .ultraLight,
                                          design: .monospaced))
                            .foregroundStyle(d == durationMin ? Color.moonlight.opacity(0.8) : Color.moonlight.opacity(0.2))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                }
            }
            .padding(.top, 24)

            // Bell picker
            VStack(spacing: 8) {
                Text("CLOCHE")
                    .font(.system(size: 9, weight: .ultraLight, design: .monospaced))
                    .foregroundStyle(Color.moonlight.opacity(0.2))
                    .tracking(3)

                HStack(spacing: 0) {
                    ForEach(bellOptions, id: \.0) { sec, label in
                        Button {
                            bellInterval = sec
                        } label: {
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

            Spacer()

            // Start button
            Button {
                showSession = true
            } label: {
                Image(systemName: "play.circle")
                    .font(.system(size: 44, weight: .ultraLight))
                    .foregroundStyle(Color.moonlight.opacity(0.35))
            }
            .padding(.bottom, 60)
        }
        .background(Color.voidBg)
        .fullScreenCover(isPresented: $showSession, onDismiss: { Task { await vm.reloadMed() } }) {
            SpiritMeditationSessionView(
                plannedSec:   durationMin * 60,
                bellInterval: bellInterval
            )
        }
    }
}

// MARK: - Active meditation session

struct SpiritMeditationSessionView: View {
    let plannedSec: Int
    let bellInterval: Int

    @Environment(\.dismiss) private var dismiss

    @State private var elapsed:     Int  = 0
    @State private var isRunning:   Bool = false
    @State private var isFinished:  Bool = false
    @State private var showControls = true
    @State private var startedAt    = Date()
    @State private var sessionTask: Task<Void, Never>?
    @State private var controlHideTask: Task<Void, Never>?

    private var remaining: Int { max(0, plannedSec - elapsed) }

    var body: some View {
        ZStack {
            Color.voidBg.ignoresSafeArea()

            // Tap to show/hide controls
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { toggleControls() }

            VStack {
                Spacer()

                // Main timer
                Text(formatTime(isFinished ? plannedSec : remaining))
                    .font(.system(size: 64, weight: .ultraLight, design: .monospaced))
                    .foregroundStyle(Color.moonlight.opacity(isFinished ? 0.6 : 0.55))
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.easeInOut(duration: 0.3), value: remaining)

                Spacer()

                if showControls || !isRunning {
                    controlsView
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.4), value: showControls)
        .onAppear { startSession() }
        .onDisappear { sessionTask?.cancel(); controlHideTask?.cancel() }
    }

    private var controlsView: some View {
        VStack(spacing: 20) {
            if isFinished {
                VStack(spacing: 12) {
                    Text("Bien.")
                        .font(.system(size: 20, weight: .ultraLight))
                        .foregroundStyle(Color.moonlight.opacity(0.55))
                    Button("Fermer") { dismiss() }
                        .font(.appLabel.weight(.ultraLight))
                        .foregroundStyle(Color.moonlight.opacity(0.3))
                }
            } else if isRunning {
                Button("Terminer") {
                    sessionTask?.cancel()
                }
                .font(.appLabel.weight(.ultraLight))
                .foregroundStyle(Color.moonlight.opacity(0.25))
            } else {
                Button {
                    startSession()
                } label: {
                    Image(systemName: "play.circle")
                        .font(.system(size: 40, weight: .ultraLight))
                        .foregroundStyle(Color.moonlight.opacity(0.35))
                }
            }
        }
        .padding(.bottom, 60)
    }

    // MARK: - Logic

    private func startSession() {
        guard !isRunning && !isFinished else { return }
        isRunning  = true
        startedAt  = Date()
        elapsed    = 0
        autoHideControls()

        sessionTask = Task { @MainActor in
            while elapsed < plannedSec {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    break
                }
                elapsed += 1

                if bellInterval > 0 && elapsed % bellInterval == 0 && elapsed < plannedSec {
                    AudioServicesPlaySystemSound(1013)
                }
            }
            await endSession(completed: elapsed >= plannedSec)
        }
    }

    @MainActor
    private func endSession(completed: Bool) async {
        isRunning  = false
        isFinished = true
        showControls = true
        controlHideTask?.cancel()
        let actual = Int(Date().timeIntervalSince(startedAt))
        AudioServicesPlaySystemSound(1013)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        try? await APIService.shared.logMeditation(
            plannedSec:   plannedSec,
            actualSec:    actual,
            bellInterval: bellInterval,
            completed:    completed
        )
    }

    private func toggleControls() {
        guard isRunning else { return }
        showControls = true
        autoHideControls()
    }

    private func autoHideControls() {
        controlHideTask?.cancel()
        controlHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { showControls = false }
        }
    }

    private func formatTime(_ sec: Int) -> String {
        let m = sec / 60, s = sec % 60
        return String(format: "%d:%02d", m, s)
    }
}
