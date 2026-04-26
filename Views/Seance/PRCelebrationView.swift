import SwiftUI

// MARK: - PR Celebration View
// Shown as fullScreenCover immediately after a session ends with ≥1 PR.
struct PRCelebrationView: View {
    let prs: [(name: String, oneRM: Double)]
    let onDismiss: () -> Void

    @ObservedObject private var units = UnitSettings.shared
    @State private var showContent = false
    @State private var showButton = false
    @State private var launched = false

    private let particles: [PRParticle] = PRParticle.generate(count: 48)

    var body: some View {
        ZStack {
            Color(hex: "080810").ignoresSafeArea()

            RadialGradient(
                colors: [Color.yellow.opacity(showContent ? 0.22 : 0), Color.clear],
                center: .center, startRadius: 0, endRadius: 350
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.9), value: showContent)

            // Confetti burst
            GeometryReader { geo in
                let cx = geo.size.width / 2
                let cy = geo.size.height * 0.38
                ForEach(particles) { p in
                    Group {
                        if p.isCircle {
                            Circle()
                                .fill(p.color)
                                .frame(width: p.size, height: p.size)
                        } else {
                            Capsule()
                                .fill(p.color)
                                .frame(width: p.size * 0.6, height: p.size * 1.8)
                                .rotationEffect(.degrees(p.angle * 180 / .pi))
                        }
                    }
                    .position(
                        x: cx + (launched ? p.distance * cos(p.angle) : 0),
                        y: cy + (launched ? p.distance * sin(p.angle) : 0)
                    )
                    .opacity(launched ? 0 : 0.92)
                    .animation(
                        .easeOut(duration: p.duration).delay(p.delay),
                        value: launched
                    )
                }
            }
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer()

                if showContent {
                    VStack(spacing: 26) {
                        // Trophy ring
                        ZStack {
                            Circle()
                                .stroke(Color.yellow.opacity(0.2), lineWidth: 1.5)
                                .frame(width: 160, height: 160)
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [Color.yellow.opacity(0.25), Color.yellow.opacity(0.04)],
                                        center: .center, startRadius: 0, endRadius: 80
                                    )
                                )
                                .frame(width: 140, height: 140)
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 62, weight: .bold))
                                .foregroundColor(.yellow)
                        }
                        .scaleEffect(showContent ? 1 : 0.2)

                        // Label + PRs
                        VStack(spacing: 14) {
                            Text(prs.count == 1 ? "RECORD PERSONNEL" : "RECORDS PERSONNELS")
                                .font(.system(size: 11, weight: .black)).tracking(3)
                                .foregroundColor(.yellow.opacity(0.7))

                            if prs.count == 1, let pr = prs.first {
                                Text(pr.name)
                                    .font(.system(size: 26, weight: .black, design: .rounded))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.yellow)
                                    Text("1RM estimé : \(units.format(pr.oneRM))")
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(.yellow)
                                }
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(Array(prs.enumerated()), id: \.offset) { _, pr in
                                        HStack {
                                            Text(pr.name)
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                            Spacer()
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.up.right")
                                                    .font(.system(size: 10, weight: .bold))
                                                Text(units.format(pr.oneRM))
                                                    .font(.system(size: 14, weight: .bold))
                                            }
                                            .foregroundColor(.yellow)
                                        }
                                        .padding(.horizontal, 20).padding(.vertical, 8)
                                        .background(Color.yellow.opacity(0.07))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                                .padding(.horizontal, 32)
                            }
                        }
                    }
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                }

                Spacer()

                if showButton {
                    Button(action: onDismiss) {
                        Text("Continuer")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(hex: "080810"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.yellow)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(SpringButtonStyle())
                    .padding(.horizontal, 32)
                    .padding(.bottom, 52)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            triggerNotificationFeedback(.success)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

            withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) {
                showContent = true
                launched = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeOut(duration: 0.35)) {
                    showButton = true
                }
            }
        }
    }
}

// MARK: - Particle data
struct PRParticle: Identifiable {
    let id = UUID()
    let angle: Double       // radians
    let distance: CGFloat
    let color: Color
    let size: CGFloat
    let duration: Double
    let delay: Double
    let isCircle: Bool

    static func generate(count: Int) -> [PRParticle] {
        let colors: [Color] = [.yellow, .orange, Color(hex: "F5C518"), .white, .cyan, .green, .pink]
        return (0..<count).map { i in
            let angle = Double.random(in: 0..<(2 * .pi))
            let distance = CGFloat.random(in: 80...260)
            return PRParticle(
                angle: angle,
                distance: distance,
                color: colors[i % colors.count],
                size: CGFloat.random(in: 5...12),
                duration: Double.random(in: 0.55...0.95),
                delay: Double.random(in: 0...0.12),
                isCircle: i % 3 != 0
            )
        }
    }
}
