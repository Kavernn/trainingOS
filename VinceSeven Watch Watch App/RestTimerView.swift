import SwiftUI
import WatchKit

struct RestTimerView: View {
    @State private var configured  = 90  // durée configurée via Crown (secondes)
    @State private var remaining   = 90
    @State private var isRunning   = false
    @State private var timerRef: Timer?

    var body: some View {
        VStack(spacing: 8) {
            Text(timeString(remaining))
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundStyle(remaining < 10 ? .red : (remaining < 30 ? .yellow : .orange))
                .focusable(!isRunning)
                .digitalCrownRotation(
                    Binding(
                        get: { Double(configured) },
                        set: {
                            configured = Int($0)
                            if !isRunning { remaining = configured }
                        }
                    ),
                    from: 10, through: 600, by: 5,
                    sensitivity: .medium,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )

            HStack(spacing: 8) {
                Button {
                    isRunning ? pause() : start()
                } label: {
                    Image(systemName: isRunning ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(isRunning ? .gray : .orange)

                Button { reset() } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }
        }
        .navigationTitle("Repos")
        .onDisappear { pause() }
    }

    private func timeString(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }

    private func start() {
        isRunning = true
        timerRef  = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            guard remaining > 0 else {
                WKInterfaceDevice.current().play(.notification)
                pause()
                return
            }
            remaining -= 1
            if remaining <= 3 && remaining > 0 {
                WKInterfaceDevice.current().play(.click)
            }
        }
    }

    private func pause() {
        isRunning = false
        timerRef?.invalidate()
        timerRef  = nil
    }

    private func reset() {
        pause()
        remaining = configured
    }
}
