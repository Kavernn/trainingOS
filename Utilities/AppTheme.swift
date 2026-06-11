import SwiftUI
import Combine

// MARK: - Theme Option

enum AppThemeOption: String, CaseIterable {
    case monochrome = "monochrome"
    case electric   = "electric"
    case blood      = "blood"

    var displayName: String {
        switch self {
        case .monochrome: return "Monochrome"
        case .electric:   return "Electric"
        case .blood:      return "Blood"
        }
    }

    var previewColor: Color {
        switch self {
        case .monochrome: return Color(hex: "1C1C1E")
        case .electric:   return Color(hex: "E8FF00")
        case .blood:      return Color(hex: "C0392B")
        }
    }
}

// MARK: - Theme Colors

struct AppThemeColors {
    let accent:          Color
    let accentLight:     Color
    let accentMuted:     Color   // was accentUltraLight
    let onAccent:        Color   // was accentText
    let background:      Color
    let surfaceCard:     Color   // was backgroundCard
    let surfaceElevated: Color   // was backgroundSecondary
    let surfaceInset:    Color   // new
    let textPrimary:     Color
    let textSecondary:   Color
    let textMuted:       Color   // was textTertiary
    let separator:       Color
    let separatorSubtle: Color
    let separatorStrong: Color
    let danger:          Color
    let success:         Color
    let warning:         Color
    let info:            Color   // new

    // Matière & Profondeur
    let cardCornerRadius: CGFloat
    let cardBorderWidth:  CGFloat
    let cardBorderColor:  Color
    let cardShadowColor:  Color
    let cardShadowRadius: CGFloat
    let cardShadowOffset: CGSize
    let cardGlowColor:    Color    // non-nil; .clear = no glow
    let cardGlowRadius:   CGFloat

    // Palette graphiques ordonnée (5 couleurs, index cyclé via chartColor(_:))
    let chartPalette: [Color]
}

extension AppThemeColors {
    static let monochrome = AppThemeColors(
        accent:          .white,
        accentLight:     Color(hex: "AEAEB2"),
        accentMuted:     Color(hex: "F2F2F7"),
        onAccent:        .black,
        background:      .black,
        surfaceCard:     Color(hex: "1C1C1E"),
        surfaceElevated: Color(hex: "2C2C2E"),
        surfaceInset:    Color(hex: "0D0D0F"),
        textPrimary:     .white,
        textSecondary:   Color.white.opacity(0.6),
        textMuted:       Color.white.opacity(0.3),
        separator:       Color.white.opacity(0.07),
        separatorSubtle: Color.white.opacity(0.04),
        separatorStrong: Color.white.opacity(0.10),
        danger:          Color(hex: "FF453A"),
        success:         Color(hex: "32D74B"),
        warning:         Color(hex: "FFD60A"),
        info:            Color(hex: "64D2FF"),
        cardCornerRadius: 8,
        cardBorderWidth:  1.0,
        cardBorderColor:  Color.white.opacity(0.12),
        cardShadowColor:  .clear,
        cardShadowRadius: 0,
        cardShadowOffset: CGSize(width: 0, height: 0),
        cardGlowColor:    .clear,
        cardGlowRadius:   0,
        chartPalette:     [.white, Color.white.opacity(0.65), Color.white.opacity(0.45),
                           Color.white.opacity(0.30), Color.white.opacity(0.18)]
    )

    static let electric = AppThemeColors(
        accent:          Color(hex: "E8FF00"),
        accentLight:     Color(hex: "F4FF66"),
        accentMuted:     Color(hex: "1E2000"),
        onAccent:        .black,
        background:      .black,
        surfaceCard:     Color(hex: "0A0A0A"),
        surfaceElevated: Color(hex: "111111"),
        surfaceInset:    Color(hex: "070710"),
        textPrimary:     .white,
        textSecondary:   Color(hex: "AAAAAA"),
        textMuted:       Color(hex: "555555"),
        separator:       Color(hex: "E8FF00").opacity(0.08),
        separatorSubtle: Color(hex: "E8FF00").opacity(0.04),
        separatorStrong: Color(hex: "E8FF00").opacity(0.15),
        danger:          Color(hex: "FF3B30"),
        success:         Color(hex: "00E5FF"),
        warning:         Color(hex: "FF9F0A"),
        info:            Color(hex: "38BDF8"),
        cardCornerRadius: 14,
        cardBorderWidth:  1.0,
        cardBorderColor:  Color(hex: "E8FF00").opacity(0.25),
        cardShadowColor:  Color(hex: "E8FF00").opacity(0.15),
        cardShadowRadius: 12,
        cardShadowOffset: CGSize(width: 0, height: 4),
        cardGlowColor:    Color(hex: "E8FF00").opacity(0.20),
        cardGlowRadius:   20,
        chartPalette:     [Color(hex: "E8FF00"), Color(hex: "00CFFF"), Color(hex: "FF6B2B"),
                           Color(hex: "C77DFF"), Color(hex: "FF3860")]
    )

    static let blood = AppThemeColors(
        accent:          Color(hex: "C0392B"),
        accentLight:     Color(hex: "E74C3C"),
        accentMuted:     Color(hex: "2D0A08"),
        onAccent:        .white,
        background:      Color(hex: "1A1A1A"),
        surfaceCard:     Color(hex: "242424"),
        surfaceElevated: Color(hex: "2E2E2E"),
        surfaceInset:    Color(hex: "1A0808"),
        textPrimary:     Color(hex: "F5F5F5"),
        textSecondary:   Color(hex: "AAAAAA"),
        textMuted:       Color(hex: "666666"),
        separator:       Color(hex: "C0392B").opacity(0.12),
        separatorSubtle: Color(hex: "C0392B").opacity(0.06),
        separatorStrong: Color(hex: "C0392B").opacity(0.22),
        danger:          Color(hex: "FF453A"),
        success:         Color(hex: "2ECC71"),
        warning:         Color(hex: "F39C12"),
        info:            Color(hex: "64D2FF"),
        cardCornerRadius: 16,
        cardBorderWidth:  1.0,
        cardBorderColor:  Color(hex: "C0392B").opacity(0.20),
        cardShadowColor:  Color(hex: "C0392B").opacity(0.25),
        cardShadowRadius: 16,
        cardShadowOffset: CGSize(width: 0, height: 4),
        cardGlowColor:    .clear,
        cardGlowRadius:   0,
        chartPalette:     [Color(hex: "E74C3C"), Color(hex: "F39C12"), Color(hex: "27AE60"),
                           Color(hex: "2980B9"), Color(hex: "8E44AD")]
    )
}

// MARK: - AppTheme

final class AppTheme: ObservableObject {
    static let shared = AppTheme()

    private static let storageKey = "app_theme"

    @Published var selectedTheme: AppThemeOption {
        didSet { UserDefaults.standard.set(selectedTheme.rawValue, forKey: Self.storageKey) }
    }

    @Published var refreshToken: UUID = UUID()

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey) ?? ""
        selectedTheme = AppThemeOption(rawValue: stored) ?? .blood
    }

    func applyTheme(_ option: AppThemeOption) {
        selectedTheme = option
        refreshToken  = UUID()
    }

    var colors: AppThemeColors {
        switch selectedTheme {
        case .monochrome: return .monochrome
        case .electric:   return .electric
        case .blood:      return .blood
        }
    }

    // Debug pilot toggle — tinted surface variants (Electric blue / Blood warm)
    @Published var debugTintedSurfaces: Bool = false

    // Raccourcis directs
    var accent:          Color { colors.accent }
    var accentLight:     Color { colors.accentLight }
    var accentMuted:     Color { colors.accentMuted }
    var onAccent:        Color { colors.onAccent }

    var background: Color {
        if debugTintedSurfaces, selectedTheme == .blood { return Color(hex: "1C1412") }
        return colors.background
    }
    var surfaceCard: Color {
        if debugTintedSurfaces {
            switch selectedTheme {
            case .electric: return Color(hex: "0D0D14")
            case .blood:    return Color(hex: "261C1A")
            default:        break
            }
        }
        return colors.surfaceCard
    }
    var surfaceElevated: Color {
        if debugTintedSurfaces {
            switch selectedTheme {
            case .electric: return Color(hex: "121220")
            case .blood:    return Color(hex: "2E2220")
            default:        break
            }
        }
        return colors.surfaceElevated
    }
    var surfaceInset: Color {
        if debugTintedSurfaces {
            switch selectedTheme {
            case .electric: return Color(hex: "060616")
            case .blood:    return Color(hex: "1F0C0A")
            default:        break
            }
        }
        return colors.surfaceInset
    }

    var textPrimary:     Color { colors.textPrimary }
    var textSecondary:   Color { colors.textSecondary }
    var textMuted:       Color { colors.textMuted }
    var separator:       Color { colors.separator }
    var separatorSubtle: Color { colors.separatorSubtle }
    var separatorStrong: Color { colors.separatorStrong }
    var danger:          Color { colors.danger }
    var success:         Color { colors.success }
    var warning:         Color { colors.warning }
    var info:            Color { colors.info }

    var cardCornerRadius: CGFloat { colors.cardCornerRadius }
    var cardBorderWidth:  CGFloat { colors.cardBorderWidth }
    var cardBorderColor:  Color   { colors.cardBorderColor }
    var cardShadowColor:  Color   { colors.cardShadowColor }
    var cardShadowRadius: CGFloat { colors.cardShadowRadius }
    var cardShadowOffset: CGSize  { colors.cardShadowOffset }
    var cardGlowColor:    Color   { colors.cardGlowColor }
    var cardGlowRadius:   CGFloat { colors.cardGlowRadius }

    // Opacités glass selon thème
    var glassOpacity: Double {
        switch selectedTheme {
        case .monochrome: return 0.1
        case .electric:   return 0.2
        case .blood:      return 0.15
        }
    }

    // Palette graphiques — accès par index cyclé
    var chartPalette: [Color] { colors.chartPalette }
    func chartColor(_ index: Int) -> Color { chartPalette[index % chartPalette.count] }

    // Gradient d'accent — teinte identitaire du thème, startPoint/endPoint configurables
    func accentGradient(startPoint: UnitPoint = .leading, endPoint: UnitPoint = .trailing) -> LinearGradient {
        switch selectedTheme {
        case .monochrome: return LinearGradient(
            colors: [.white, Color(hex: "A0A0A0")],
            startPoint: startPoint, endPoint: endPoint)
        case .electric:   return LinearGradient(
            colors: [Color(hex: "E8FF00"), Color(hex: "B8CC00")],
            startPoint: startPoint, endPoint: endPoint)
        case .blood:      return LinearGradient(
            colors: [Color(hex: "E74C3C"), Color(hex: "7B241C")],
            startPoint: startPoint, endPoint: endPoint)
        }
    }
}
