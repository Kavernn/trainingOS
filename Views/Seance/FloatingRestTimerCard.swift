import SwiftUI

struct FloatingRestTimerCard: View {
    @ObservedObject private var timer = RestTimerManager.shared

    var body: some View {
        TimelineView(.periodic(from: timer.startDate ?? .now, by: 1)) { ctx in
            let elapsed = timer.isRunning ? max(0, ctx.date.timeIntervalSince(timer.startDate ?? .now)) : Double(timer.totalSeconds - timer.remaining)
            let remaining = max(0, timer.totalSeconds - Int(elapsed))
            let progress = timer.totalSeconds > 0 ? Double(remaining) / Double(timer.totalSeconds) : 0
            let ringColor: Color = progress > 0.6 ? .green : (progress > 0.3 ? .orange : .red)

            VStack(spacing: 22) {
                if let name = timer.exerciseName {
                    Text(name.uppercased())
                        .font(.appCaption.weight(.semibold))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.07), lineWidth: 16)
                        .frame(width: 160, height: 160)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(ringColor.opacity(0.28), style: StrokeStyle(lineWidth: 24, lineCap: .round))
                        .frame(width: 160, height: 160)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: progress)
                        .blur(radius: 8)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .frame(width: 160, height: 160)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: progress)

                    Text(formatTime(remaining))
                        .font(.system(size: 58, weight: .black, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }

                if timer.isRunning {
                    HStack(spacing: 16) {
                        Button {
                            timer.adjust(by: -10)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Text("−10s")
                                .font(.appLabel.weight(.semibold))
                                .foregroundColor(ringColor.opacity(0.85))
                                .padding(.horizontal, 16).padding(.vertical, 7)
                                .background(ringColor.opacity(0.1))
                                .cornerRadius(20)
                                .overlay(RoundedRectangle(cornerRadius: 20).stroke(ringColor.opacity(0.25), lineWidth: 1))
                        }
                        Button {
                            timer.adjust(by: 10)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Text("+10s")
                                .font(.appLabel.weight(.semibold))
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

                HStack(spacing: 28) {
                    Button { timer.reset() } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.appHeadline)
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

                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                            timer.dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.appLabel.weight(.bold))
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
    }

    private func formatTime(_ s: Int) -> String {
        "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}
