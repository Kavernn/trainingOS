import SwiftUI

// MARK: - PR Celebration View
// Shown as fullScreenCover immediately after a session ends with ≥1 PR.
struct PRCelebrationView: View {
    let prs: [(name: String, oneRM: Double)]
    let onDismiss: () -> Void

    @ObservedObject private var units = UnitSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showContent = false
    @State private var showButton = false
    @State private var launched = false

    private let particles: [PRParticle] = PRParticle.generate(count: 48)

    private var prAccessibilityLabel: String {
        if prs.count == 1, let pr = prs.first {
            return "Nouvelle limite détruite : \(pr.name). Nouveau record estimé : \(pr.oneRM, specifier: "%.1f")."
        }
        let names = prs.map { $0.name }.joined(separator: ", ")
        return "\(prs.count) nouvelles limites détruites : \(names)."
    }

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            RadialGradient(
                colors: [Color.yellow.opacity(showContent ? 0.22 : 0), Color.clear],
                center: .center, startRadius: 0, endRadius: 350
            )
            .ignoresSafeArea()
            .animation(reduceMotion ? .none : .easeInOut(duration: 0.9), value: showContent)

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
                        reduceMotion ? .none : .easeOut(duration: p.duration).delay(p.delay),
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
                            Text(prs.count == 1 ? "LIMITE DÉTRUITE" : "LIMITES DÉTRUITES")
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
                                    Text("Nouvelle frontière : \(units.format(pr.oneRM))")
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
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                }

                Spacer()

                if showButton {
                    Button(action: onDismiss) {
                        Text("Continuer")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color.appBg)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.yellow)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(SpringButtonStyle())
                    .accessibilityLabel("Continuer")
                    .padding(.horizontal, 32)
                    .padding(.bottom, 52)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(prAccessibilityLabel)
        .preferredColorScheme(.dark)
        .onAppear {
            triggerNotificationFeedback(.success)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

            withAnimation(reduceMotion ? .easeIn(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.68)) {
                showContent = true
                if !reduceMotion { launched = true }
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

// MARK: - Confetti (used in AlreadyLoggedSeanceView)
struct ConfettiPiece: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var color: Color
    var angle: Double
    var size: CGFloat
}

struct ConfettiView: View {
    private let colors: [Color] = [.orange, .green, .cyan, .yellow, .pink, .purple]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pieces: [ConfettiPiece] = []
    @State private var animate = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { p in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(p.color)
                        .frame(width: p.size, height: p.size * 0.5)
                        .position(x: p.x, y: animate ? geo.size.height + 40 : p.y)
                        .rotationEffect(.degrees(p.angle + (animate ? 360 : 0)))
                        .opacity(animate ? 0 : 1)
                        .animation(
                            reduceMotion ? .none : .easeIn(duration: Double.random(in: 1.4...2.4))
                                .delay(Double.random(in: 0...0.5)),
                            value: animate
                        )
                }
            }
            .onAppear {
                pieces = (0..<60).map { _ in
                    ConfettiPiece(
                        x: CGFloat.random(in: 0...geo.size.width),
                        y: CGFloat.random(in: -20...geo.size.height * 0.4),
                        color: colors.randomElement()!,
                        angle: Double.random(in: 0...360),
                        size: CGFloat.random(in: 6...12)
                    )
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    if !reduceMotion { animate = true }
                }
            }
        }
    }
}
