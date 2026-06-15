import SwiftUI

// MARK: - Type Scale
// 7 niveaux — remplace 40 tailles ad-hoc
// Mapping : voir docs/typography_migration.md

extension Font {
    /// 42pt — métriques principales, design et poids lus depuis le thème actif
    static var appHero: Font {
        .system(size: 42, weight: AppTheme.shared.displayWeight, design: AppTheme.shared.heroFontDesign)
    }

    /// 22pt — titres de sections, design et poids lus depuis le thème actif
    static var appTitle: Font {
        .system(size: 22, weight: AppTheme.shared.displayWeight, design: AppTheme.shared.titleFontDesign)
    }

    /// Métrique hero expanded — taille, poids et design lus depuis le thème actif
    static var appCardHero: Font {
        .system(size: AppTheme.shared.heroNumberSize, weight: AppTheme.shared.displayWeight, design: AppTheme.shared.heroFontDesign)
    }

    /// Métrique hero compact (preview) — heroNumberSize - 6, mêmes poids/design
    static var appCardMetric: Font {
        .system(size: AppTheme.shared.heroNumberSize - 6, weight: AppTheme.shared.displayWeight, design: AppTheme.shared.heroFontDesign)
    }

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
    var cornerRadius: CGFloat? = nil  // nil = use AppTheme.cardCornerRadius

    private var resolvedRadius: CGFloat {
        cornerRadius ?? AppTheme.shared.cardCornerRadius
    }

    func body(content: Content) -> some View {
        let theme      = AppTheme.shared
        let style      = theme.cardStyle
        let borderW    = style == .outlined ? theme.cardBorderWidth * 2.0 : theme.cardBorderWidth
        let glowColor  = style == .floating ? theme.cardGlowColor   : .clear
        let shadowColor = (style == .floating || style == .raised) ? theme.cardShadowColor : .clear
        let borderCol  = theme.colors.accentDistribution == .surgical
            ? Color.white.opacity(0.08)
            : theme.cardBorderColor
        return content
            .background(RoundedRectangle(cornerRadius: resolvedRadius).fill(Color.appCard))
            .overlay(RoundedRectangle(cornerRadius: resolvedRadius).stroke(borderCol, lineWidth: borderW))
            .clipShape(RoundedRectangle(cornerRadius: resolvedRadius))
            .shadow(color: glowColor, radius: theme.cardGlowRadius, x: 0, y: 0)
            .shadow(color: shadowColor, radius: theme.cardShadowRadius,
                    x: theme.cardShadowOffset.width, y: theme.cardShadowOffset.height)
    }
}

struct GlassCardAccent: ViewModifier {
    var accent: Color
    var cornerRadius: CGFloat? = nil  // nil = use AppTheme.cardCornerRadius

    private var resolvedRadius: CGFloat {
        cornerRadius ?? AppTheme.shared.cardCornerRadius
    }

    func body(content: Content) -> some View {
        let theme       = AppTheme.shared
        let style       = theme.cardStyle
        let borderW     = style == .outlined ? theme.cardBorderWidth * 2.0 : theme.cardBorderWidth
        let isSurgical  = theme.colors.accentDistribution == .surgical
        let glowColor   = style == .floating && !isSurgical ? accent.opacity(0.10) : Color.clear
        let shadowColor = (style == .floating || style == .raised) && !isSurgical ? accent.opacity(0.08) : Color.clear
        let fillColor   = isSurgical ? Color.clear : accent.opacity(theme.cardAccentFillOpacity)
        let strokeColor = isSurgical ? Color.white.opacity(0.08) : accent.opacity(theme.colors.cardAccentStrokeOpacity)
        return content
            .background(
                RoundedRectangle(cornerRadius: resolvedRadius)
                    .fill(Color.appCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: resolvedRadius)
                            .fill(fillColor)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: resolvedRadius)
                    .stroke(strokeColor, lineWidth: borderW)
            )
            .clipShape(RoundedRectangle(cornerRadius: resolvedRadius))
            .shadow(color: glowColor, radius: 12, x: 0, y: 0)
            .shadow(color: shadowColor, radius: 8, x: 0, y: 4)
    }
}

extension View {
    func glassCard(color: Color = .white, intensity: Double = 0.06, cornerRadius: CGFloat? = nil) -> some View {
        modifier(GlassCard(color: color, intensity: intensity, cornerRadius: cornerRadius))
    }

    func glassCardAccent(_ accent: Color, cornerRadius: CGFloat? = nil) -> some View {
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
                        AppTheme.shared.accentGradient(startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 58, height: 58)
                    .shadow(color: Color.forge.opacity(0.30), radius: 12, x: 0, y: 6)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.onAccent)
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
        let theme = AppTheme.shared
        let label = theme.sectionTitleUppercased ? title.uppercased() : title
        HStack {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .tracking(theme.sectionTitleTracking)
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
            IdentityLayerView(style: AppTheme.shared.identityLayer)
            RadialGradient(
                colors: [color.opacity(0.15), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 300
            )
            if AppTheme.shared.colors.accentDistribution == .pervasive {
                // Forge warmth — chaleur de fond constante, indépendante de la couleur d'accent
                RadialGradient(
                    colors: [Color.forge.opacity(0.08), .clear],
                    center: .bottom,
                    startRadius: 0,
                    endRadius: 220
                )
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Identity Layer View

struct IdentityLayerView: View {
    let style: IdentityLayerStyle

    var body: some View {
        Canvas { ctx, size in
            switch style {
            case .none:
                break
            case .scanlines(let opacity):
                Self.drawScanlines(ctx: &ctx, size: size, opacity: opacity)
            case .neonHalo(let color, let intensity):
                Self.drawNeonHalo(ctx: &ctx, size: size, color: color, intensity: intensity)
            case .filmGrain(let opacity):
                Self.drawFilmGrain(ctx: &ctx, size: size, opacity: opacity)
            case .goldFiligree(let opacity):
                Self.drawGoldFiligree(ctx: &ctx, size: size, opacity: opacity)
            case .cyberGrid(let opacity):
                Self.drawCyberGrid(ctx: &ctx, size: size, opacity: opacity)
            case .arcticFrost(let opacity):
                Self.drawArcticFrost(ctx: &ctx, size: size, opacity: opacity)
            case .bloodVein(let opacity):
                Self.drawBloodVein(ctx: &ctx, size: size, opacity: opacity)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    // Scanlines horizontales — Matrix
    private static func drawScanlines(ctx: inout GraphicsContext, size: CGSize, opacity: Double) {
        let step: CGFloat = 5
        var y: CGFloat = 1
        while y < size.height {
            ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                     with: .color(.white.opacity(opacity)))
            y += step
        }
    }

    // Halo néon en haut d'écran — Tokyo
    private static func drawNeonHalo(ctx: inout GraphicsContext, size: CGSize, color: Color, intensity: Double) {
        let cx = size.width / 2
        let ellipses: [(CGFloat, CGFloat, Double)] = [
            (size.width * 0.90, 110, intensity * 0.40),
            (size.width * 0.60, 70,  intensity * 0.28),
            (size.width * 0.30, 40,  intensity * 0.16)
        ]
        for (w, h, alpha) in ellipses {
            ctx.fill(Path(ellipseIn: CGRect(x: cx - w / 2, y: -h * 0.55, width: w, height: h)),
                     with: .color(color.opacity(alpha)))
        }
        // Fine ligne lumineuse au bord supérieur
        ctx.fill(Path(CGRect(x: cx - size.width * 0.25, y: 0, width: size.width * 0.50, height: 1.5)),
                 with: .color(color.opacity(intensity * 0.75)))
    }

    // Grain de film statique — Sin City
    private static func drawFilmGrain(ctx: inout GraphicsContext, size: CGSize, opacity: Double) {
        var rng = Xorshift(seed: 9876)
        let count = Int(size.width * size.height / 250)
        for _ in 0..<count {
            let x = rng.nextFloat() * size.width
            let y = rng.nextFloat() * size.height
            let r = rng.nextFloat() * 1.0 + 0.3
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                     with: .color(.white.opacity(opacity)))
        }
    }

    // Filigrane doré aux 4 coins — Gold Noir
    private static func drawGoldFiligree(ctx: inout GraphicsContext, size: CGSize, opacity: Double) {
        let c = Color(hex: "D4AF37").opacity(opacity)
        let len: CGFloat = 38
        let m: CGFloat = 18
        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: m, y: m + len), CGPoint(x: m, y: m), CGPoint(x: m + len, y: m)),
            (CGPoint(x: size.width - m - len, y: m), CGPoint(x: size.width - m, y: m), CGPoint(x: size.width - m, y: m + len)),
            (CGPoint(x: m, y: size.height - m - len), CGPoint(x: m, y: size.height - m), CGPoint(x: m + len, y: size.height - m)),
            (CGPoint(x: size.width - m - len, y: size.height - m), CGPoint(x: size.width - m, y: size.height - m), CGPoint(x: size.width - m, y: size.height - m - len))
        ]
        for (a, corner, d) in corners {
            var path = Path()
            path.move(to: a)
            path.addLine(to: corner)
            path.addLine(to: d)
            ctx.stroke(path, with: .color(c), lineWidth: 1.0)
            ctx.fill(Path(ellipseIn: CGRect(x: corner.x - 2, y: corner.y - 2, width: 4, height: 4)),
                     with: .color(c))
        }
    }

    // Grille cyber — Electric
    private static func drawCyberGrid(ctx: inout GraphicsContext, size: CGSize, opacity: Double) {
        let c = Color.white.opacity(opacity)
        let step: CGFloat = 40
        var x: CGFloat = 0
        while x <= size.width {
            var p = Path()
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: size.height))
            ctx.stroke(p, with: .color(c), lineWidth: 0.5)
            x += step
        }
        var y: CGFloat = 0
        while y <= size.height {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(p, with: .color(c), lineWidth: 0.5)
            y += step
        }
    }

    // Cristaux hexagonaux dans les coins supérieurs — Arctic
    private static func drawArcticFrost(ctx: inout GraphicsContext, size: CGSize, opacity: Double) {
        let c = Color.white.opacity(opacity)
        func hexPath(center: CGPoint, radius: CGFloat) -> Path {
            var p = Path()
            for i in 0..<6 {
                let angle = CGFloat(i) * .pi / 3 - .pi / 6
                let pt = CGPoint(x: center.x + cos(angle) * radius,
                                 y: center.y + sin(angle) * radius)
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            p.closeSubpath()
            return p
        }
        let crystals: [(CGPoint, CGFloat)] = [
            (CGPoint(x: 28, y: 70), 20), (CGPoint(x: 60, y: 42), 13), (CGPoint(x: 52, y: 95), 8),
            (CGPoint(x: size.width - 28, y: 70), 20), (CGPoint(x: size.width - 60, y: 42), 13),
            (CGPoint(x: size.width - 52, y: 95), 8)
        ]
        for (center, r) in crystals {
            ctx.stroke(hexPath(center: center, radius: r), with: .color(c), lineWidth: 0.75)
        }
    }

    // Nervures organiques dans le coin inférieur gauche — Blood
    private static func drawBloodVein(ctx: inout GraphicsContext, size: CGSize, opacity: Double) {
        let c = Color(hex: "C0392B").opacity(opacity)
        let h = size.height
        var main = Path()
        main.move(to: CGPoint(x: 0, y: h))
        main.addCurve(to: CGPoint(x: 80, y: h - 150),
                      control1: CGPoint(x: 8, y: h - 60), control2: CGPoint(x: 45, y: h - 110))
        main.addCurve(to: CGPoint(x: 140, y: h - 240),
                      control1: CGPoint(x: 108, y: h - 170), control2: CGPoint(x: 128, y: h - 205))
        ctx.stroke(main, with: .color(c), lineWidth: 1.2)
        var b1 = Path()
        b1.move(to: CGPoint(x: 80, y: h - 150))
        b1.addCurve(to: CGPoint(x: 28, y: h - 210),
                    control1: CGPoint(x: 58, y: h - 162), control2: CGPoint(x: 38, y: h - 185))
        ctx.stroke(b1, with: .color(c), lineWidth: 0.7)
        var b2 = Path()
        b2.move(to: CGPoint(x: 80, y: h - 150))
        b2.addCurve(to: CGPoint(x: 118, y: h - 185),
                    control1: CGPoint(x: 88, y: h - 158), control2: CGPoint(x: 108, y: h - 170))
        ctx.stroke(b2, with: .color(c), lineWidth: 0.6)
    }
}

// MARK: - Xorshift RNG (film grain determinism)

private struct Xorshift: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 1 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
    mutating func nextFloat() -> CGFloat {
        CGFloat(next() >> 40) / CGFloat(1 << 24)
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
