import SwiftUI

// MARK: - Glass Card Modifier
struct GlassCard: ViewModifier {
    var color: Color = .white
    var intensity: Double = 0.06
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color(hex: "11111c"))
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(intensity), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.07), .white.opacity(0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 5)
    }
}

struct GlassCardAccent: ViewModifier {
    var accent: Color
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color(hex: "11111c"))
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.12), accent.opacity(0.03), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [accent.opacity(0.35), accent.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: accent.opacity(0.15), radius: 20, x: 0, y: 8)
    }
}

extension View {
    func glassCard(color: Color = .white, intensity: Double = 0.06, cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassCard(color: color, intensity: intensity, cornerRadius: cornerRadius))
    }

    func glassCardAccent(_ accent: Color, cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassCardAccent(accent: accent, cornerRadius: cornerRadius))
    }
}

// MARK: - Spring Button Style
struct SpringButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Appear Animation
struct AppearModifier: ViewModifier {
    let delay: Double
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .onAppear {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82).delay(delay)) {
                    appeared = true
                }
            }
    }
}

extension View {
    func appearAnimation(delay: Double = 0) -> some View {
        modifier(AppearModifier(delay: delay))
    }
}

// MARK: - Floating Action Button
struct FAB: View {
    let icon: String
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange, Color(hex: "e05500")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 58, height: 58)
                    .shadow(color: .orange.opacity(0.30), radius: 12, x: 0, y: 6)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(SpringButtonStyle(scale: 0.93))
    }
}

// MARK: - Section Header
struct SectionLabel: View {
    let title: String
    var icon: String? = nil
    var action: (() -> Void)? = nil
    var actionLabel: String = "Voir tout"

    var body: some View {
        HStack {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.4))
            Spacer()
            if let action = action {
                Button(actionLabel, action: action)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange)
            }
        }
    }
}

// MARK: - Glow Text
struct GlowText: ViewModifier {
    let color: Color
    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.6), radius: 8, x: 0, y: 0)
            .shadow(color: color.opacity(0.3), radius: 16, x: 0, y: 0)
    }
}

extension View {
    func glow(_ color: Color) -> some View {
        modifier(GlowText(color: color))
    }
}

// MARK: - Pulsing Dot
struct PulsingDot: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 12, height: 12)
                .scaleEffect(pulse ? 1.6 : 1.0)
                .opacity(pulse ? 0 : 0.8)
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

// MARK: - Streak Badge
struct StreakBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            Text("🔥")
                .font(.system(size: 14))
            Text("\(count) jours")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.orange)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12))
        .overlay(Capsule().stroke(Color.orange.opacity(0.3), lineWidth: 1))
        .clipShape(Capsule())
    }
}

// MARK: - Ambient Background
struct AmbientBackground: View {
    let color: Color

    var body: some View {
        ZStack {
            Color(hex: "080810")
            RadialGradient(
                colors: [color.opacity(0.12), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 300
            )
            RadialGradient(
                colors: [Color.purple.opacity(0.05), .clear],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 250
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Tab Bar Clearance
/// Bottom padding to clear the custom tab bar (tab content ~60pt + safe area inset)
var fabBottomPadding: CGFloat {
#if targetEnvironment(macCatalyst)
    return 0
#elseif os(iOS)
    let safeBottom = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first?.windows.first?.safeAreaInsets.bottom ?? 0
    return safeBottom + 60
#else
    return 60
#endif
}

/// Bottom content padding for scroll views — 0 on Mac (no tab bar), 80 on iOS
var contentBottomPadding: CGFloat {
#if targetEnvironment(macCatalyst)
    return 0
#else
    return 80
#endif
}

// MARK: - Stat Pill
struct StatPill: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .black))
                .foregroundColor(color)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .glassCard(color: color, intensity: 0.05)
    }
}
