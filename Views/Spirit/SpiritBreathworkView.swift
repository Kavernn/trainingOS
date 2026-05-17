import SwiftUI

// MARK: - Protocol selector tab

struct SpiritBreathTabView: View {
    @ObservedObject var vm: SpiritViewModel
    @State private var activeSession: BreathworkProtocol?
    @State private var triggeredFrom: String = "standalone"

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                ForEach(BreathworkProtocol.allCases, id: \.self) { proto in
                    protocolCard(proto)
                }

                if !vm.breathSessions.isEmpty {
                    recentSection
                }
            }
            .padding(20)
        }
        .background(Color.voidBg)
        .fullScreenCover(item: $activeSession) { proto in
            SpiritBreathSessionView(
                def: BreathProtocolDef.forProtocol(proto),
                triggeredFrom: triggeredFrom
            ) {
                activeSession = nil
                Task { await vm.reloadBreath() }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("BREATHWORK")
                .font(.system(size: 10, weight: .light, design: .monospaced))
                .foregroundStyle(Color.moonlight.opacity(0.35))
                .tracking(4)
            Text("3 protocoles. Pas plus.")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(Color.moonlight.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func protocolCard(_ proto: BreathworkProtocol) -> some View {
        Button {
            triggeredFrom = "standalone"
            activeSession = proto
        } label: {
            HStack(spacing: 16) {
                Image(systemName: proto.systemIcon)
                    .font(.system(size: 18, weight: .ultraLight))
                    .foregroundStyle(Color.moonlight.opacity(0.6))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(proto.displayName)
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(Color.moonlight.opacity(0.9))
                    Text(proto.subtitle)
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(Color.moonlight.opacity(0.35))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(Color.moonlight.opacity(0.2))
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.moonlight.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.moonlight.opacity(0.08), lineWidth: 0.5))
            )
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RÉCENT")
                .font(.system(size: 9, weight: .light, design: .monospaced))
                .foregroundStyle(Color.moonlight.opacity(0.25))
                .tracking(3)

            ForEach(vm.breathSessions.prefix(5)) { s in
                HStack {
                    Text(BreathworkProtocol(rawValue: s.protocol_.rawValue)?.displayName ?? s.protocol_.rawValue)
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(Color.moonlight.opacity(0.5))
                    Spacer()
                    Text(formattedDuration(s.durationSec))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.moonlight.opacity(0.3))
                    Text(shortDate(s.startedAt))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.moonlight.opacity(0.2))
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func formattedDuration(_ sec: Int) -> String {
        let m = sec / 60, s = sec % 60
        return s == 0 ? "\(m)m" : "\(m)m\(s)s"
    }

    private func shortDate(_ iso: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.locale = Locale(identifier: "fr_CA")
        guard let d = f.date(from: String(iso.prefix(19))) else { return "" }
        f.dateFormat = "d MMM"
        return f.string(from: d)
    }
}

// MARK: - Full-screen breath session

struct SpiritBreathSessionView: View {
    let def: BreathProtocolDef
    let triggeredFrom: String
    let onDismiss: () -> Void

    @State private var circleScale:    CGFloat = 0.55
    @State private var circleOpacity:  Double  = 0.06
    @State private var phaseLabel:     String  = ""
    @State private var countdown:      Int     = 0
    @State private var cyclesCompleted: Int    = 0
    @State private var isActive        = false
    @State private var isFinished      = false
    @State private var startedAt       = Date()
    @State private var sessionTask:    Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.voidBg.ignoresSafeArea()

            // Ambient glow behind circle
            RadialGradient(
                colors: [Color.moonlight.opacity(circleOpacity * 0.8), Color.clear],
                center: .center, startRadius: 0, endRadius: 200
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: Double(currentPhaseDuration)), value: circleOpacity)

            VStack(spacing: 0) {
                Spacer()

                // Phase label
                Text(isFinished ? "TERMINÉ" : (isActive ? phaseLabel : "PRÊT"))
                    .font(.system(size: 11, weight: .light, design: .monospaced))
                    .foregroundStyle(Color.moonlight.opacity(0.4))
                    .tracking(5)
                    .frame(height: 20)
                    .padding(.bottom, 40)

                // The living circle
                ZStack {
                    Circle()
                        .strokeBorder(Color.moonlight.opacity(0.15), lineWidth: 0.8)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.moonlight.opacity(0.07), Color.clear],
                                center: .center, startRadius: 0, endRadius: 100
                            )
                        )
                }
                .frame(width: 200, height: 200)
                .scaleEffect(circleScale)

                // Countdown
                Text(isActive && countdown > 0 ? "\(countdown)" : "")
                    .font(.system(size: 28, weight: .ultraLight, design: .monospaced))
                    .foregroundStyle(Color.moonlight.opacity(0.3))
                    .frame(height: 40)
                    .padding(.top, 36)

                // Cycles
                if isActive {
                    cyclesDots
                        .padding(.top, 20)
                }

                Spacer()

                // Control
                if isFinished {
                    finishedView
                } else if !isActive {
                    startButton
                } else {
                    stopButton
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
        .onDisappear { sessionTask?.cancel() }
    }

    // MARK: - Subviews

    private var cyclesDots: some View {
        let target = def.targetCycles
        let shown  = min(target, 12)
        return HStack(spacing: 5) {
            ForEach(0..<shown, id: \.self) { i in
                Circle()
                    .fill(i < cyclesCompleted ? Color.moonlight.opacity(0.5) : Color.moonlight.opacity(0.08))
                    .frame(width: 5, height: 5)
            }
            if target > shown {
                Text("+\(target - shown)")
                    .font(.system(size: 9, weight: .light))
                    .foregroundStyle(Color.moonlight.opacity(0.2))
            }
        }
    }

    private var startButton: some View {
        Button {
            beginSession()
        } label: {
            Image(systemName: "play.circle")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(Color.moonlight.opacity(0.4))
        }
    }

    private var stopButton: some View {
        Button {
            sessionTask?.cancel()
        } label: {
            Text("Terminer")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(Color.moonlight.opacity(0.3))
        }
        .padding(.bottom, 8)
    }

    private var finishedView: some View {
        VStack(spacing: 16) {
            Text("Bien.")
                .font(.system(size: 22, weight: .ultraLight))
                .foregroundStyle(Color.moonlight.opacity(0.6))

            Button("Fermer") { onDismiss() }
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(Color.moonlight.opacity(0.35))
        }
    }

    // MARK: - Session logic

    private var currentPhaseDuration: Int {
        guard !def.steps.isEmpty else { return 4 }
        return def.steps[0].duration
    }

    private func beginSession() {
        startedAt  = Date()
        isActive   = true
        sessionTask = Task { @MainActor in
            await runSession()
        }
    }

    @MainActor
    private func runSession() async {
        let steps = def.steps
        let total = def.targetCycles

        outer: for _ in 0..<total {
            for step in steps {
                phaseLabel = step.label

                withAnimation(.easeInOut(duration: Double(step.duration))) {
                    circleScale   = step.endScale
                    circleOpacity = step.endScale > 0.7 ? 0.14 : 0.04
                }

                UIImpactFeedbackGenerator(style: .light).impactOccurred()

                for remaining in stride(from: step.duration, through: 1, by: -1) {
                    countdown = remaining
                    do {
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                    } catch {
                        break outer
                    }
                }
                countdown = 0

                if step.countsCycle { cyclesCompleted += 1 }
            }
        }

        await finishSession()
    }

    @MainActor
    private func finishSession() async {
        isActive   = false
        isFinished = true
        let duration = Int(Date().timeIntervalSince(startedAt))
        withAnimation(.easeInOut(duration: 0.8)) {
            circleScale   = 0.78
            circleOpacity = 0.08
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        try? await APIService.shared.logBreathwork(
            protocol: def.id,
            durationSec: duration,
            cycles: cyclesCompleted,
            triggeredFrom: triggeredFrom
        )
    }
}

// MARK: - BreathworkProtocol as Identifiable (for fullScreenCover)
extension BreathworkProtocol: Identifiable {
    public var id: String { rawValue }
}
