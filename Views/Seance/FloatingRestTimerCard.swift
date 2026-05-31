import SwiftUI

struct FloatingRestTimerCard: View {
    @ObservedObject private var timer = RestTimerManager.shared

    private var ringColor: Color {
        if timer.progress > 0.6 { return .green }
        if timer.progress > 0.3 { return .orange }
        return .red
    }

    var body: some View {
        VStack(spacing: 22) {
            if let name = timer.exerciseName {
                Text(name.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
            }

            // Circular clock
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.07), lineWidth: 16)
                    .frame(width: 160, height: 160)

                // Glow arc
                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(ringColor.opacity(0.28), style: StrokeStyle(lineWidth: 24, lineCap: .round))
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: timer.progress)
                    .blur(radius: 8)

                // Main arc
                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: timer.progress)

                Text(formatTime(timer.remaining))
                    .font(.system(size: 58, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            // +10 / -10 adjustment buttons (visible only while running)
            if timer.isRunning {
                HStack(spacing: 16) {
                    Button { timer.adjust(by: -10) } label: {
                        Text("−10s")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(ringColor.opacity(0.85))
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .background(ringColor.opacity(0.1))
                            .cornerRadius(20)
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(ringColor.opacity(0.25), lineWidth: 1))
                    }
                    Button { timer.adjust(by: 10) } label: {
                        Text("+10s")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(ringColor.opacity(0.85))
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .background(ringColor.opacity(0.1))
                            .cornerRadius(20)
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(ringColor.opacity(0.25), lineWidth: 1))
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .animation(.easeInOut(duration: 0.2), value: timer.isRunning)
            }

            // Controls
            HStack(spacing: 28) {
                Button { timer.reset() } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(width: 50, height: 50)
                        .background(Color.white.opacity(0.09))
                        .clipShape(Circle())
                }

                Button {
                    if timer.isRunning { timer.stop() } else { timer.resume() }
                } label: {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 68, height: 68)
                        .background(ringColor)
                        .clipShape(Circle())
                        .shadow(color: ringColor.opacity(0.55), radius: 14, y: 5)
                }
                .animation(.easeInOut(duration: 0.25), value: timer.isRunning)

                // Close — stops and dismisses the timer completely
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        timer.dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.45))
                        .frame(width: 50, height: 50)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 24)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.appBg.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(ringColor.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.55), radius: 32, x: 0, y: -8)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func formatTime(_ s: Int) -> String {
        "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}
