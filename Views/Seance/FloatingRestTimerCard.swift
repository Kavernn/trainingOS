import SwiftUI

struct FloatingRestTimerCard: View {
    @ObservedObject private var timer = RestTimerManager.shared

    var body: some View {
        TimelineView(.periodic(from: timer.startDate ?? .now, by: 1)) { ctx in
            let elapsed = timer.isRunning ? max(0, ctx.date.timeIntervalSince(timer.startDate ?? .now)) : Double(timer.totalSeconds - timer.remaining)
            let remaining = max(0, timer.totalSeconds - Int(elapsed))
            let progress = timer.totalSeconds > 0 ? Double(remaining) / Double(timer.totalSeconds) : 0
            let ringColor: Color = progress > 0.6 ? .statusGreen : (progress > 0.3 ? .statusOrange : .statusRed)

            VStack(spacing: 8) {
                // Ligne 1 : chrono + barre de progression horizontale
                VStack(spacing: 4) {
                    Text(formatTime(remaining))
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundColor(ringColor)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .frame(maxWidth: .infinity)

                    // ponytail: barre horizontale remplace le cercle 160pt d'avant.
                    // Même progress + même ringColor → feedback visuel préservé.
                    // scaleEffect(x: progress, anchor: .leading) évite un GeometryReader
                    // greedy qui bypassait le padding parent.
                    Capsule()
                        .fill(Color.appSurfaceInset)
                        .frame(height: 4)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(ringColor)
                                .frame(height: 4)
                                .scaleEffect(x: max(0, progress), y: 1, anchor: .leading)
                                .animation(.linear(duration: 1), value: progress)
                        }
                }

                // Ligne 2 : contrôles alignés — ±10s toujours visibles (évite
                // le layout jump entre running / pausé).
                HStack(spacing: 8) {
                    Button {
                        timer.adjust(by: -10)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text("−10s")
                            .font(.appLabel.weight(.semibold))
                            .foregroundColor(ringColor.opacity(0.85))
                            .frame(width: 52, height: 40)
                            .background(ringColor.opacity(0.1))
                            .cornerRadius(14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ringColor.opacity(0.25), lineWidth: 1))
                    }

                    Button {
                        timer.adjust(by: 10)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text("+10s")
                            .font(.appLabel.weight(.semibold))
                            .foregroundColor(ringColor.opacity(0.85))
                            .frame(width: 52, height: 40)
                            .background(ringColor.opacity(0.1))
                            .cornerRadius(14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ringColor.opacity(0.25), lineWidth: 1))
                    }

                    Spacer()

                    Button { timer.reset() } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.appBody.weight(.semibold))
                            .foregroundColor(Color.appOnSurface.opacity(0.55))
                            .frame(width: 44, height: 44)
                            .background(Color.appSurfaceInset)
                            .clipShape(Circle())
                    }

                    Button {
                        if timer.isRunning { timer.stop() } else { timer.resume() }
                    } label: {
                        Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 48, height: 48)
                            .background(ringColor)
                            .clipShape(Circle())
                            .shadow(color: ringColor.opacity(0.45), radius: 8, y: 3)
                    }
                    .animation(.easeInOut(duration: 0.25), value: timer.isRunning)

                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                            timer.dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.appLabel.weight(.bold))
                            .foregroundColor(Color.appOnSurface.opacity(0.45))
                            .frame(width: 44, height: 44)
                            .background(Color.appSurfaceInset)
                            .clipShape(Circle())
                    }
                }
                // ponytail: override .tint(theme.accent) racine (ContentView L80)
                // qui projetait un halo orange sur chaque bouton via le style auto iOS 26.
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            // ponytail: containerRelativeFrame lit la largeur du container ambiant
            // (ScrollView bornée à l'écran) au lieu de proposer ∞ au safeAreaInset,
            // ce qui étirait la ScrollView (cf. régression chantier B).
            .containerRelativeFrame(.horizontal) { length, _ in length - 32 }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.appBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(ringColor.opacity(0.3), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.45), radius: 12, x: 0, y: -4)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func formatTime(_ s: Int) -> String {
        "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}
