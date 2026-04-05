import SwiftUI
import AVFoundation
import UserNotifications

struct TimerView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("timer_workSecs")    private var workSecs    = 40
    @AppStorage("timer_restSecs")    private var restSecs    = 20
    @AppStorage("timer_prepareSecs") private var prepareSecs = 5
    @AppStorage("timer_totalRounds") private var totalRounds = 8
    @State private var currentRound = 1
    @State private var phase: TimerPhase = .idle
    @State private var remaining = 40
    @State private var running = false
    @State private var timerTask: Task<Void, Never>? = nil
    @State private var beepPlayer: AVAudioPlayer?

    enum TimerPhase: String { case idle, prepare, work, rest, done }

    // UserDefaults keys for background persistence
    private static let bgPhaseEndKey = "timerBgPhaseEnd"
    private static let bgPhaseKey    = "timerBgPhase"
    private static let bgRoundKey    = "timerBgRound"
    private static let bgWorkKey     = "timerBgWork"
    private static let bgRestKey     = "timerBgRest"
    private static let bgPrepareKey  = "timerBgPrepare"
    private static let bgTotalKey    = "timerBgTotal"

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

                // Round dots — centred, size adapts to count
                RoundDotsView(
                    totalRounds: totalRounds,
                    currentRound: currentRound,
                    phase: phase,
                    phaseColor: phaseColor
                )

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
        .onDisappear { persistState() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                persistState()
                scheduleBackgroundNotifications()
            } else if newPhase == .active {
                cancelBackgroundNotifications()
                syncFromBackground()
            }
        }
    }

    // MARK: - Helpers
    private func formatTime(_ s: Int) -> String {
        "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    private func toggleTimer() {
        if running {
            stopTimer()
        } else {
            UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound]) { _, _ in }
            if phase == .idle || phase == .done {
                currentRound = 1
                phase = .prepare
                remaining = prepareSecs
            }
            running = true
            timerTask = Task { await runLoop() }
            persistState()
        }
    }

    private func stopTimer() {
        running = false
        timerTask?.cancel()
        timerTask = nil
        cancelBackgroundNotifications()
        clearPersistedState()
    }

    // MARK: - Background persistence

    private func persistState() {
        guard running else { clearPersistedState(); return }
        let ud = UserDefaults.standard
        ud.set(Date().addingTimeInterval(TimeInterval(remaining)), forKey: Self.bgPhaseEndKey)
        ud.set(phase.rawValue, forKey: Self.bgPhaseKey)
        ud.set(currentRound,   forKey: Self.bgRoundKey)
        ud.set(workSecs,       forKey: Self.bgWorkKey)
        ud.set(restSecs,       forKey: Self.bgRestKey)
        ud.set(prepareSecs,    forKey: Self.bgPrepareKey)
        ud.set(totalRounds,    forKey: Self.bgTotalKey)
    }

    private func clearPersistedState() {
        let ud = UserDefaults.standard
        for key in [Self.bgPhaseEndKey, Self.bgPhaseKey, Self.bgRoundKey,
                    Self.bgWorkKey, Self.bgRestKey, Self.bgPrepareKey, Self.bgTotalKey] {
            ud.removeObject(forKey: key)
        }
    }

    // Schedule a notification for every upcoming phase transition (max 64 — iOS limit).
    private func scheduleBackgroundNotifications() {
        guard running, phase != .done, phase != .idle else { return }
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        var delay    = TimeInterval(remaining)
        var curPhase = phase
        var curRound = currentRound
        var idx      = 0

        while idx < 60 {
            // Determine the phase that follows the current one
            let (nextPhase, nextRound): (TimerPhase, Int) = {
                switch curPhase {
                case .prepare: return (.work, curRound)
                case .work:    return curRound >= totalRounds ? (.done, curRound) : (.rest, curRound)
                case .rest:    return (.work, curRound + 1)
                default:       return (.done, curRound)
                }
            }()

            let content   = UNMutableNotificationContent()
            content.sound = .default
            switch nextPhase {
            case .work:
                content.title = "WORK ⚡"
                content.body  = "Round \(nextRound)/\(totalRounds) — \(formatTime(workSecs))"
            case .rest:
                content.title = "REST 💤"
                content.body  = "Round \(curRound)/\(totalRounds) — \(formatTime(restSecs))"
            case .done:
                content.title = "TERMINÉ 🔥"
                content.body  = "\(totalRounds) rounds complétés !"
            default:
                break
            }

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "timer_bg_\(idx)", content: content, trigger: trigger)
            )
            idx += 1
            if nextPhase == .done { break }

            curPhase = nextPhase
            curRound = nextRound
            delay += nextPhase == .work ? TimeInterval(workSecs) : TimeInterval(restSecs)
        }
    }

    private func cancelBackgroundNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    private func syncFromBackground() {
        let ud = UserDefaults.standard
        guard let phaseEnd = ud.object(forKey: Self.bgPhaseEndKey) as? Date,
              let phaseRaw = ud.string(forKey: Self.bgPhaseKey),
              let bgPhase  = TimerPhase(rawValue: phaseRaw) else { return }

        let storedWork    = ud.integer(forKey: Self.bgWorkKey)
        let storedRest    = ud.integer(forKey: Self.bgRestKey)
        let storedPrepare = ud.integer(forKey: Self.bgPrepareKey)
        let storedTotal   = ud.integer(forKey: Self.bgTotalKey)
        var bgRound       = ud.integer(forKey: Self.bgRoundKey)

        workSecs    = storedWork    > 0 ? storedWork    : workSecs
        restSecs    = storedRest    > 0 ? storedRest    : restSecs
        prepareSecs = storedPrepare > 0 ? storedPrepare : prepareSecs
        totalRounds = storedTotal   > 0 ? storedTotal   : totalRounds

        var elapsed = -phaseEnd.timeIntervalSinceNow  // positive = past end
        var curPhase = bgPhase

        if elapsed <= 0 {
            // Still in current phase
            phase = curPhase
            currentRound = bgRound
            remaining = max(0, Int(phaseEnd.timeIntervalSinceNow.rounded()))
            if !running {
                running = true
                timerTask = Task { await runLoop() }
            }
            return
        }

        // Advance through phases mathematically
        func phaseDuration(_ p: TimerPhase) -> Int {
            switch p {
            case .prepare: return storedPrepare > 0 ? storedPrepare : prepareSecs
            case .work:    return storedWork    > 0 ? storedWork    : workSecs
            case .rest:    return storedRest    > 0 ? storedRest    : restSecs
            default:       return 0
            }
        }

        func nextPhase(_ p: TimerPhase) -> (TimerPhase, Bool) {
            // Returns next phase and whether round incremented
            switch p {
            case .prepare: return (.work, false)
            case .work:
                if bgRound >= totalRounds { return (.done, false) }
                return (.rest, false)
            case .rest:
                bgRound += 1
                return (.work, true)
            default: return (.done, false)
            }
        }

        while elapsed > 0 && curPhase != .done {
            let dur = phaseDuration(curPhase)
            if elapsed >= Double(dur) {
                elapsed -= Double(dur)
                (curPhase, _) = nextPhase(curPhase)
            } else {
                break
            }
        }

        if curPhase == .done {
            phase = .done
            running = false
            clearPersistedState()
        } else {
            let dur = phaseDuration(curPhase)
            phase = curPhase
            currentRound = bgRound
            remaining = max(0, dur - Int(elapsed.rounded()))
            if !running {
                running = true
                timerTask = Task { await runLoop() }
            }
            persistState()
        }
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
            triggerImpact(style: .rigid)
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
                // Done feedback
                triggerImpact(style: .heavy)
                beepPlayer = makeBeep(hz: 660, duration: 0.4)
                beepPlayer?.play()
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

// MARK: - Round Dots
struct RoundDotsView: View {
    let totalRounds: Int
    let currentRound: Int
    let phase: TimerView.TimerPhase
    let phaseColor: Color

    private var dotSize: CGFloat {
        switch totalRounds {
        case ...8:  return 14
        case ...14: return 11
        case ...22: return 9
        case ...32: return 7
        default:    return 6
        }
    }

    private var dotSpacing: CGFloat {
        switch totalRounds {
        case ...8:  return 10
        case ...14: return 7
        case ...22: return 5
        default:    return 4
        }
    }

    private func dotColor(_ i: Int) -> Color {
        if i < currentRound { return .orange }
        if i == currentRound && phase != .idle { return phaseColor }
        return Color(hex: "191926")
    }

    var body: some View {
        Group {
            if totalRounds <= 32 {
                // Tous les dots tiennent — centré
                HStack(spacing: dotSpacing) {
                    ForEach(1...max(1, totalRounds), id: \.self) { i in
                        Circle()
                            .fill(dotColor(i))
                            .frame(width: dotSize, height: dotSize)
                            .animation(.easeInOut(duration: 0.25), value: currentRound)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 20)
            } else {
                // Trop de rounds — scroll horizontal avec dots centrés au départ
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(1...max(1, totalRounds), id: \.self) { i in
                            Circle()
                                .fill(dotColor(i))
                                .frame(width: 6, height: 6)
                                .animation(.easeInOut(duration: 0.25), value: currentRound)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
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
