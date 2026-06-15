import SwiftUI

struct SessionTimerView: View {
    @ObservedObject var chrono: WorkoutChronoViewModel

    private var formattedTime: String {
        let mm = chrono.elapsedSeconds / 60
        let ss = chrono.elapsedSeconds % 60
        return String(format: "%d:%02d", mm, ss)
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: chrono.isPaused ? "pause.fill" : "clock")
                .font(.system(size: 10))
            Text(formattedTime)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
        }
        .foregroundColor(chrono.isPaused ? Color.forge.opacity(0.75) : Color.statusCyan.opacity(0.75))
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(chrono.isPaused ? Color.forge.opacity(0.1) : Color.statusCyan.opacity(0.08))
        .cornerRadius(8)
        .animation(.easeInOut(duration: 0.2), value: chrono.isPaused)
        .onTapGesture { chrono.togglePause() }
        .transition(.opacity)
    }
}
