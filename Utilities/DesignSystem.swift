import SwiftUI

// MARK: - Type Scale
// 7 niveaux — remplace 40 tailles ad-hoc
// Mapping : voir docs/typography_migration.md

extension Font {
    /// 34pt bold rounded — métriques principales (Phoenix, readiness, chrono)
    static let appHero = Font.system(size: 34, weight: .bold, design: .rounded)

    /// 22pt bold rounded — titres de sections, headers de cards
    static let appTitle = Font.system(size: 22, weight: .bold, design: .rounded)

    /// 17pt semibold — noms d'exercices, titres de vues
    static let appHeadline = Font.system(size: 17, weight: .semibold, design: .default)

    /// 15pt regular — corps de texte, descriptions
    static let appBody = Font.system(size: 15, weight: .regular, design: .default)

    /// 13pt medium — labels de métriques, sous-titres
    static let appLabel = Font.system(size: 13, weight: .medium, design: .default)

    /// 11pt regular — timestamps, metadata, notes secondaires
    static let appCaption = Font.system(size: 11, weight: .regular, design: .default)

    /// 9pt regular — badges, tags, indicateurs très discrets
    static let appMicro = Font.system(size: 9, weight: .regular, design: .default)
}

// MARK: - Card Modifiers
struct GlassCard: ViewModifier {
    var color: Color = .white   // kept for call-site compatibility, unused
    var intensity: Double = 0.06
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.appCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.forge.opacity(AppTheme.shared.glassOpacity), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
    }
}

struct GlassCardAccent: ViewModifier {
    var accent: Color
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.appCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(accent.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: accent.opacity(0.10), radius: 12, x: 0, y: 4)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Appear Animation
struct AppearModifier: ViewModifier {
    let delay: Double
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 10)
            .onAppear {
                if reduceMotion {
                    appeared = true
                } else {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82).delay(delay)) {
                        appeared = true
                    }
                }
            }
    }
}

extension View {
    func appearAnimation(delay: Double = 0) -> some View {
        modifier(AppearModifier(delay: delay))
    }
}

// MARK: - Hot Appear Animation (intensity level 4-5)
struct HotAppearModifier: ViewModifier {
    let delay: Double
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.88)
            .onAppear {
                if reduceMotion {
                    appeared = true
                } else {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.60).delay(delay)) {
                        appeared = true
                    }
                }
            }
    }
}

extension View {
    func appearAnimationHot(delay: Double = 0) -> some View {
        modifier(HotAppearModifier(delay: delay))
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
                            colors: [Color.forge, Color.forgeDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 58, height: 58)
                    .shadow(color: Color.forge.opacity(0.30), radius: 12, x: 0, y: 6)
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
                    .foregroundColor(.forge)
            }
        }
    }
}

// MARK: - Glow Text (no-op — removed flashy shadow effect)
struct GlowText: ViewModifier {
    let color: Color
    func body(content: Content) -> some View { content }
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
                .foregroundColor(.forge)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.forge.opacity(0.12))
        .overlay(Capsule().stroke(Color.forge.opacity(0.3), lineWidth: 1))
        .clipShape(Capsule())
    }
}

// MARK: - Ambient Background
struct AmbientBackground: View {
    let color: Color

    var body: some View {
        ZStack {
            Color.appBg
            RadialGradient(
                colors: [color.opacity(0.10), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 300
            )
            // Forge warmth — chaleur de fond constante, indépendante de la couleur d'accent
            RadialGradient(
                colors: [Color.forge.opacity(0.04), .clear],
                center: .bottom,
                startRadius: 0,
                endRadius: 220
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

// MARK: - Empty Chart Placeholder
struct EmptyChartPlaceholder: View {
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.gray.opacity(0.4))
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .glassCard(color: .white, intensity: 0.03)
    }
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

// MARK: - StatCard
/// KPI card — superset of KPICard + HealthKPICard. Use for all new stat cards.
struct StatCard: View {
    let value: String
    let label: String
    let color: Color
    var subtitle: String? = nil       // secondary period label (below label)
    var delta: (String, Color)? = nil // day-over-day delta (between value and label)

    private var isNull: Bool { value == "—" }

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 22, weight: .black))
                .foregroundColor(isNull ? .gray.opacity(0.35) : color)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let (str, col) = delta {
                Text(str)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(col)
            }
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.3)
                .foregroundColor(.gray.opacity(0.65))
                .textCase(.uppercase)
                .lineLimit(1)
            if let sub = subtitle {
                Text(sub)
                    .font(.system(size: 8))
                    .foregroundColor(.gray.opacity(0.45))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .glassCard(color: isNull ? .gray : color, intensity: isNull ? 0.02 : 0.05)
        .cornerRadius(12)
    }
}

// MARK: - ProgressRing
/// Circular progress ring with optional center content.
/// Covers full-circle rings (0–100%); for 270° gauge arcs use inline trim(0, 0.75*pct)+rotation.
struct ProgressRing<Center: View>: View {

    let progress: Double
    let color: Color
    var size: CGFloat = 80
    var lineWidth: CGFloat = 10
    var backgroundColor: Color = Color.appSurfaceInset
    var animation: Animation = .easeOut(duration: 0.6)
    @ViewBuilder let centerContent: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(backgroundColor, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(animation, value: progress)
            centerContent()
        }
        .frame(width: size, height: size)
    }
}

extension ProgressRing where Center == EmptyView {
    init(
        progress: Double,
        color: Color,
        size: CGFloat = 80,
        lineWidth: CGFloat = 10,
        backgroundColor: Color = Color.appSurfaceInset,
        animation: Animation = .easeOut(duration: 0.6)
    ) {
        self.init(progress: progress, color: color, size: size, lineWidth: lineWidth,
                  backgroundColor: backgroundColor, animation: animation) { EmptyView() }
    }
}

// MARK: - ChipButton
/// Pill-shaped toggle chip — selected/unselected states with color tinting
struct ChipButton: View {

    let label: String
    let isSelected: Bool
    var color: Color = Color.forge
    var size: Size = .medium
    let action: () -> Void

    enum Size {
        case small   // 12pt semibold, h:12 v:6  (dense filter rows)
        case medium  // 13pt semibold, h:14 v:7  (tab-level navigation)
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: fontSize, weight: .semibold))
                .padding(.horizontal, hPadding)
                .padding(.vertical, vPadding)
                .background(isSelected ? color.opacity(0.2) : Color.appSurfaceInset)
                .foregroundColor(isSelected ? color : .gray)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? color.opacity(0.5) : Color.clear, lineWidth: 1))
        }
    }

    private var fontSize: CGFloat  { size == .small ? 12 : 13 }
    private var hPadding: CGFloat  { size == .small ? 12 : 14 }
    private var vPadding: CGFloat  { size == .small ? 6  : 7  }
}

// MARK: - LoadingSkeleton
/// Prebuilt skeleton placeholders — compose SkeletonBar directly for custom layouts
struct LoadingSkeleton: View {

    enum Style {
        case metric                 // value bar + label bar (MetricCell shape)
        case row                    // circle + 2 text lines (list row)
        case card                   // full card block placeholder
        case text(lines: Int)       // N stacked text bars, varying widths
        case circle(size: CGFloat)  // circular avatar or badge
    }

    var style: Style = .metric

    var body: some View {
        switch style {
        case .metric:
            metricBody
        case .row:
            rowBody
        case .card:
            cardBody
        case .text(let lines):
            textBody(lines: lines)
        case .circle(let size):
            circleBody(size: size)
        }
    }

    private var metricBody: some View {
        VStack(alignment: .center, spacing: 4) {
            SkeletonBar(width: 44, height: 15)
            SkeletonBar(width: 36, height: 10)
        }
    }

    private var rowBody: some View {
        HStack(spacing: 12) {
            SkeletonBar(width: 36, height: 36, radius: 18)
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBar(width: 120, height: 13)
                SkeletonBar(width: 80, height: 10)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var cardBody: some View {
        SkeletonBar(height: 80, radius: 14)
    }

    @ViewBuilder
    private func textBody(lines: Int) -> some View {
        let widths: [CGFloat] = [200, 160, 180, 140, 170, 120]
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<lines, id: \.self) { i in
                SkeletonBar(width: widths[i % widths.count], height: 13)
            }
        }
    }

    private func circleBody(size: CGFloat) -> some View {
        SkeletonBar(width: size, height: size, radius: size / 2)
    }
}
