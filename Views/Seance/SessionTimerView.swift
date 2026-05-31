import SwiftUI

struct SessionTimerView: View {
    let sessionStart: Date

    var body: some View {
        TimelineView(.periodic(from: sessionStart, by: 1)) { ctx in
            let elapsed = max(0, ctx.date.timeIntervalSince(sessionStart))
            let mm = Int(elapsed) / 60
            let ss = Int(elapsed) % 60
            HStack(spacing: 3) {
                Image(systemName: "clock").font(.system(size: 10))
                Text(String(format: "%d:%02d", mm, ss))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            .foregroundColor(.cyan.opacity(0.75))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.cyan.opacity(0.08))
            .cornerRadius(8)
        }
        .transition(.opacity)
    }
}
