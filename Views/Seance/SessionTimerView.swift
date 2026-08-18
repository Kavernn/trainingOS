import SwiftUI

struct SessionTimerView: View {
    @ObservedObject var chrono: WorkoutChronoViewModel

    private var formattedTime: String {
        let mm = chrono.elapsedSeconds / 60
        let ss = chrono.elapsedSeconds % 60
        return String(format: "%d:%02d", mm, ss)
    }

    var body: some View {
        let isPaused = chrono.isPaused
        let fgOpacity: Double = isPaused ? 0.6 : 0.95
        let strokeOpacity: Double = isPaused ? 0.15 : 0.30
        HStack(spacing: 3) {
            Image(systemName: isPaused ? "pause.fill" : "clock")
                .font(.system(size: 10))
            Text(formattedTime)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
        }
        .foregroundColor(Color.forge.opacity(fgOpacity))
        .padding(.horizontal, 8).padding(.vertical, 5)
        .glassCard(cornerRadius: 8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.forge.opacity(strokeOpacity), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: chrono.isPaused)
        .onTapGesture { chrono.togglePause() }
        .transition(.opacity)
    }
}
