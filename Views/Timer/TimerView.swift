import SwiftUI

struct TimerView: View {
    @State private var workSecs = 40
    @State private var restSecs = 20
    @State private var totalRounds = 8
    @State private var currentRound = 1
    @State private var phase: TimerPhase = .idle
    @State private var remaining = 40
    @State private var running = false
    @State private var timer: Foundation.Timer?

    enum TimerPhase { case idle, work, rest, done }

    var phaseColor: Color {
        switch phase {
        case .work: return .orange
        case .rest: return .green
        case .done: return .green
        case .idle: return .gray
        }
    }

    var progress: Double {
        switch phase {
        case .work: return Double(remaining) / Double(workSecs)
        case .rest: return Double(remaining) / Double(restSecs)
        default:    return 1.0
        }
    }

    var phaseLabel: String {
        switch phase {
        case .work: return "⚡ WORK"
        case .rest: return "💤 REST"
        case .done: return "✅ TERMINÉ"
        case .idle: return "PRÊT"
        }
    }

    var body: some View {
        ZStack {
            Color(hex: "080810").ignoresSafeArea()

            VStack(spacing: 24) {
                // Phase label
                Text(phaseLabel)
                    .font(.system(size: 12, weight: .bold))
                    .tracking(4)
                    .foregroundColor(phaseColor)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                    .background(phaseColor.opacity(0.12))
                    .cornerRadius(6)

                // Ring
                ZStack {
                    Circle()
                        .stroke(Color(hex: "191926"), lineWidth: 12)
                        .frame(width: 220, height: 220)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(phaseColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: 220, height: 220)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.25), value: progress)

                    VStack(spacing: 4) {
                        Text(formatTime(remaining))
                            .font(.system(size: 64, weight: .black, design: .rounded))
                            .foregroundColor(phaseColor)
                            .monospacedDigit()
                        if phase != .idle {
                            Text("ROUND \(currentRound) / \(totalRounds)")
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(2)
                                .foregroundColor(.gray)
                        }
                    }
                }

                // Controls
                HStack(spacing: 20) {
                    Button(action: resetTimer) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 56, height: 56)
                            .background(Color(hex: "191926"))
                            .foregroundColor(.gray)
                            .clipShape(Circle())
                    }

                    Button(action: toggleTimer) {
                        Image(systemName: running ? "pause.fill" : "play.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .frame(width: 72, height: 72)
                            .background(running ? Color.orange.opacity(0.15) : Color.orange)
                            .foregroundColor(running ? .orange : .white)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(running ? Color.orange : Color.clear, lineWidth: 2))
                    }

                    Button(action: skipPhase) {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 56, height: 56)
                            .background(Color(hex: "191926"))
                            .foregroundColor(.gray)
                            .clipShape(Circle())
                    }
                }

                // Settings
                HStack(spacing: 10) {
                    SettingCard(title: "💤 REST", value: "\(restSecs)s", color: .green) {
                        HStack(spacing: 6) {
                            Button("-5s") { restSecs = max(5, restSecs - 5); if !running { resetTimer() } }
                                .settingBtnStyle()
                            Button("+5s") { restSecs += 5; if !running { resetTimer() } }
                                .settingBtnStyle()
                        }
                    }
                    SettingCard(title: "⚡ WORK", value: "\(workSecs)s", color: .orange) {
                        HStack(spacing: 6) {
                            Button("-5s") { workSecs = max(5, workSecs - 5); if !running { resetTimer() } }
                                .settingBtnStyle()
                            Button("+5s") { workSecs += 5; if !running { resetTimer() } }
                                .settingBtnStyle()
                        }
                    }
                }

                // Rounds
                HStack {
                    Text("🔁 ROUNDS")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(2)
                        .foregroundColor(.gray)
                    Spacer()
                    Button("-1") { totalRounds = max(1, totalRounds - 1); if !running { resetTimer() } }
                        .settingBtnStyle()
                    Text("\(totalRounds)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.blue)
                        .frame(width: 40)
                    Button("+1") { totalRounds = min(99, totalRounds + 1); if !running { resetTimer() } }
                        .settingBtnStyle()
                }
                .padding(14)
                .background(Color(hex: "11111c"))
                .cornerRadius(12)

                // Round dots
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(1...totalRounds, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(i < currentRound ? Color.orange :
                                      (i == currentRound && phase == .rest) ? Color.orange :
                                      Color(hex: "191926"))
                                .frame(width: 14, height: 14)
                        }
                    }
                    .padding(.horizontal, 2)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
        }
    }

    private func formatTime(_ s: Int) -> String {
        "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    private func toggleTimer() {
        if running {
            running = false
            timer?.invalidate()
            timer = nil
        } else {
            if phase == .idle || phase == .done {
                currentRound = 1
                phase = .work
                remaining = workSecs
            }
            running = true
            timer = Foundation.Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                tick()
            }
        }
    }

    private func tick() {
        guard running else { return }
        remaining -= 1
        if remaining <= 0 {
            switch phase {
            case .work:
                if currentRound >= totalRounds {
                    phase = .done; running = false; timer?.invalidate()
                } else {
                    phase = .rest; remaining = restSecs
                }
            case .rest:
                currentRound += 1; phase = .work; remaining = workSecs
            default: break
            }
        }
    }

    private func resetTimer() {
        running = false; timer?.invalidate(); timer = nil
        phase = .idle; currentRound = 1; remaining = workSecs
    }

    private func skipPhase() {
        switch phase {
        case .work:
            if currentRound >= totalRounds { phase = .done; running = false; timer?.invalidate() }
            else { phase = .rest; remaining = restSecs }
        case .rest:
            currentRound += 1; phase = .work; remaining = workSecs
        default: break
        }
    }
}

struct SettingCard<Content: View>: View {
    let title: String
    let value: String
    let color: Color
    @ViewBuilder let buttons: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 26, weight: .black))
                .foregroundColor(color)
            buttons()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "11111c"))
        .cornerRadius(12)
    }
}

extension View {
    func settingBtnStyle() -> some View {
        self
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06))
            .cornerRadius(6)
    }
}
