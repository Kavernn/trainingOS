import SwiftUI
import AVFoundation

struct TimerView: View {
    @State private var workSecs = 40
    @State private var restSecs = 20
    @State private var prepareSecs = 5
    @State private var totalRounds = 8
    @State private var currentRound = 1
    @State private var phase: TimerPhase = .idle
    @State private var remaining = 40
    @State private var running = false
    @State private var timerTask: Task<Void, Never>? = nil
    @State private var beepPlayer: AVAudioPlayer?

    enum TimerPhase { case idle, prepare, work, rest, done }

    var phaseColor: Color {
        switch phase {
        case .prepare: return .yellow
        case .work:    return .orange
        case .rest:    return .green
        case .done:    return .green
        case .idle:    return .gray
        }
    }

    var progress: Double {
        switch phase {
        case .prepare: return prepareSecs > 0 ? Double(remaining) / Double(prepareSecs) : 1
        case .work:    return workSecs > 0 ? Double(remaining) / Double(workSecs) : 1
        case .rest:    return restSecs > 0 ? Double(remaining) / Double(restSecs) : 1
        default:       return 1.0
        }
    }

    var phaseLabel: String {
        switch phase {
        case .prepare: return "PRÉPARE"
        case .work:    return "WORK"
        case .rest:    return "REST"
        case .done:    return "TERMINÉ"
        case .idle:    return "PRÊT"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                // Phase badge
                Text(phaseLabel)
                    .font(.system(size: 12, weight: .black))
                    .tracking(4)
                    .foregroundColor(phaseColor)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 7)
                    .background(phaseColor.opacity(0.12))
                    .clipShape(Capsule())
                    .padding(.top, 12)

                // Ring
                ZStack {
                    Circle()
                        .stroke(Color(hex: "191926"), lineWidth: 14)
                        .frame(width: 200, height: 200)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(phaseColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.3), value: progress)

                    VStack(spacing: 4) {
                        Text(formatTime(remaining))
                            .font(.system(size: 58, weight: .black, design: .rounded))
                            .foregroundColor(phaseColor)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        if phase == .work || phase == .rest {
                            Text("ROUND \(currentRound) / \(totalRounds)")
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(2)
                                .foregroundColor(.gray)
                        }
                    }
                }

                // −5s / +5s ajustement du décompte actif
                if phase != .idle && phase != .done {
                    HStack(spacing: 16) {
                        Button {
                            remaining = max(1, remaining - 5)
                        } label: {
                            Text("−5s")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(phaseColor)
                                .frame(width: 72, height: 36)
                                .background(phaseColor.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(phaseColor.opacity(0.3), lineWidth: 1))
                        }
                        Button {
                            remaining += 5
                        } label: {
                            Text("+5s")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(phaseColor)
                                .frame(width: 72, height: 36)
                                .background(phaseColor.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(phaseColor.opacity(0.3), lineWidth: 1))
                        }
                    }
                }

                // Play / Reset / Skip
                HStack(spacing: 20) {
                    CircleButton(icon: "arrow.counterclockwise", size: 52, color: .gray) {
                        stopTimer()
                        phase = .idle; currentRound = 1; remaining = prepareSecs
                    }
                    CircleButton(
                        icon: running ? "pause.fill" : "play.fill",
                        size: 68,
                        color: .orange,
                        filled: !running
                    ) { toggleTimer() }
                    CircleButton(icon: "forward.end.fill", size: 52, color: .gray) {
                        skipPhase()
                    }
                }

                // Round dots
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(1...max(1, totalRounds), id: \.self) { i in
                            Circle()
                                .fill(i < currentRound ? Color.orange :
                                      i == currentRound && phase != .idle ? phaseColor :
                                      Color(hex: "191926"))
                                .frame(width: 12, height: 12)
                                .animation(.easeInOut(duration: 0.2), value: currentRound)
                        }
                    }
                    .padding(.horizontal, 4)
                }

                Divider().background(Color.white.opacity(0.07))

                // Settings — PRÉPARE, WORK, REST, ROUNDS (désactivés pendant le run)
                VStack(spacing: 10) {
                    TimerStepperRow(
                        label: "⏱  PRÉPARE",
                        value: $prepareSecs,
                        color: .yellow,
                        step: 1,
                        min: 1,
                        max: 60,
                        onChanged: { _ in }
                    )
                    TimerStepperRow(
                        label: "⚡  WORK",
                        value: $workSecs,
                        color: .orange,
                        step: 5,
                        min: 5,
                        max: 300,
                        onChanged: { _ in if !running { remaining = workSecs; phase = .idle } }
                    )
                    TimerStepperRow(
                        label: "💤  REST",
                        value: $restSecs,
                        color: .green,
                        step: 5,
                        min: 5,
                        max: 300,
                        onChanged: { _ in }
                    )
                    TimerStepperRow(
                        label: "🔁  ROUNDS",
                        value: $totalRounds,
                        color: .blue,
                        step: 1,
                        min: 1,
                        max: 99,
                        onChanged: { _ in }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .disabled(running)
                .opacity(running ? 0.4 : 1)
            }
        }
        .background(AmbientBackground(color: phaseColor))
        .onDisappear { stopTimer() }
    }

    // MARK: - Helpers
    private func formatTime(_ s: Int) -> String {
        "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    private func toggleTimer() {
        if running {
            stopTimer()
        } else {
            if phase == .idle || phase == .done {
                currentRound = 1
                phase = .prepare
                remaining = prepareSecs
            }
            running = true
            timerTask = Task { await runLoop() }
        }
    }

    private func stopTimer() {
        running = false
        timerTask?.cancel()
        timerTask = nil
    }

    @MainActor
    private func runLoop() async {
        while running && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard running && !Task.isCancelled else { break }
            tick()
        }
    }

    private func tick() {
        guard running, remaining > 0 else {
            if remaining <= 0 { advance() }
            return
        }
        remaining -= 1
        if remaining <= 3 && remaining > 0 {
            beepPlayer = makeBeep(hz: 880, duration: 0.12)
            beepPlayer?.play()
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
        if remaining <= 0 { advance() }
    }

    private func advance() {
        switch phase {
        case .prepare:
            phase = .work
            remaining = workSecs
        case .work:
            if currentRound >= totalRounds {
                phase = .done
                running = false
                timerTask?.cancel()
            } else {
                phase = .rest
                remaining = restSecs
            }
        case .rest:
            currentRound += 1
            phase = .work
            remaining = workSecs
        default:
            break
        }
    }

    private func skipPhase() {
        switch phase {
        case .prepare:
            phase = .work; remaining = workSecs
        case .work:
            if currentRound >= totalRounds {
                phase = .done; running = false; timerTask?.cancel()
            } else {
                phase = .rest; remaining = restSecs
            }
        case .rest:
            currentRound += 1; phase = .work; remaining = workSecs
        case .idle:
            currentRound = 1; phase = .prepare; remaining = prepareSecs
            running = true
            timerTask = Task { await runLoop() }
        default:
            break
        }
    }
}

// MARK: - Stepper Row
struct TimerStepperRow: View {
    let label: String
    @Binding var value: Int
    let color: Color
    let step: Int
    let min: Int
    let max: Int
    var onChanged: (Int) -> Void

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .tracking(1)
                .foregroundColor(.white)
                .frame(width: 100, alignment: .leading)

            Spacer()

            HStack(spacing: 0) {
                Button {
                    if value - step >= min {
                        value -= step
                        onChanged(value)
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .foregroundColor(value - step >= min ? .white : .gray.opacity(0.3))
                }

                Text("\(value)\(step > 1 ? "s" : "")")
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(color)
                    .frame(width: 64, alignment: .center)
                    .monospacedDigit()

                Button {
                    if value + step <= max {
                        value += step
                        onChanged(value)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .foregroundColor(value + step <= max ? color : .gray.opacity(0.3))
                }
            }
            .background(Color(hex: "191926"))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(hex: "11111c"))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Circle Button
struct CircleButton: View {
    let icon: String
    let size: CGFloat
    let color: Color
    var filled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.35, weight: .semibold))
                .frame(width: size, height: size)
                .background(filled ? color : color.opacity(0.12))
                .foregroundColor(filled ? .white : color)
                .clipShape(Circle())
                .overlay(Circle().stroke(filled ? Color.clear : color.opacity(0.3), lineWidth: 1.5))
                .shadow(color: filled ? color.opacity(0.4) : .clear, radius: 12, y: 4)
        }
        .buttonStyle(SpringButtonStyle(scale: 0.92))
    }
}
