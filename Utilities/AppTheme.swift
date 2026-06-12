import SwiftUI
import Combine

// MARK: - Theme Option

enum AppThemeOption: String, CaseIterable {
    case monochrome = "monochrome"
    case sinCity    = "sinCity"
    case blood      = "blood"
    case electric   = "electric"
    case matrix     = "matrix"
    case tokyo      = "tokyo"
    case arctic     = "arctic"
    case goldNoir   = "goldNoir"
    case desert     = "desert"

    var displayName: String {
        switch self {
        case .monochrome: return "Monochrome"
        case .sinCity:    return "Sin City"
        case .blood:      return "Blood"
        case .electric:   return "Electric"
        case .matrix:     return "Matrix"
        case .tokyo:      return "Tokyo"
        case .arctic:     return "Arctic Frost"
        case .goldNoir:   return "Gold Noir"
        case .desert:     return "Desert"
        }
    }

    var previewColor: Color {
        switch self {
        case .monochrome: return Color(hex: "1C1C1E")
        case .sinCity:    return Color(hex: "FF1E1E")
        case .blood:      return Color(hex: "C0392B")
        case .electric:   return Color(hex: "E8FF00")
        case .matrix:     return Color(hex: "00FF66")
        case .tokyo:      return Color(hex: "8B5CF6")
        case .arctic:     return Color(hex: "7DD3FC")
        case .goldNoir:   return Color(hex: "D4AF37")
        case .desert:     return Color(hex: "E9C46A")
        }
    }
}

// MARK: - Theme Colors

struct AppThemeColors {
    let accent:          Color
    let accentLight:     Color
    let accentMuted:     Color
    let onAccent:        Color
    let background:      Color
    let surfaceCard:     Color
    let surfaceElevated: Color
    let surfaceInset:    Color
    let textPrimary:     Color
    let textSecondary:   Color
    let textMuted:       Color
    let separator:       Color
    let separatorSubtle: Color
    let separatorStrong: Color
    let danger:          Color
    let success:         Color
    let warning:         Color
    let info:            Color

    // Matière & Profondeur
    let cardCornerRadius: CGFloat
    let cardBorderWidth:  CGFloat
    let cardBorderColor:  Color
    let cardShadowColor:  Color
    let cardShadowRadius: CGFloat
    let cardShadowOffset: CGSize
    let cardGlowColor:    Color
    let cardGlowRadius:   CGFloat

    // Palette graphiques ordonnée (5 couleurs, index cyclé via chartColor(_:))
    let chartPalette: [Color]

    // Matière globale & identité — absorbés ici pour que chaque thème soit autocontenu
    let glassOpacity:         Double
    let accentGradientColors: [Color]
}

// MARK: - Règle design : teintes de fond exclusives par thème (catalogue 9)
// Noir pur (Monochrome) · Micro rouge-chaud (Sin City) · Rouge-brun (Blood)
// Vert forêt (Electric) · Phosphore vert froid (Matrix) · Nuit violet (Tokyo)
// Océan teal-bleu (Arctic) · Micro doré (Gold Noir) · Sable brun (Desert)
// Tout nouveau thème revendique une teinte de fond non prise ou se distingue
// au test 1-seconde face à tous les thèmes existants, fond sur fond.
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
        chartPalette:          [.white, Color.white.opacity(0.65), Color.white.opacity(0.45),
                                Color.white.opacity(0.30), Color.white.opacity(0.18)],
        glassOpacity:          0.10,
        accentGradientColors:  [.white, Color(hex: "A0A0A0")]
    )

    // Film noir, détective. Tout est noir et blanc sauf le sang.
    static let sinCity = AppThemeColors(
        accent:          Color(hex: "FF1E1E"),
        accentLight:     Color(hex: "FF5555"),
        accentMuted:     Color(hex: "1A0000"),
        onAccent:        Color(hex: "F0F0F0"),
        background:      Color(hex: "060403"),
        surfaceCard:     Color(hex: "0E0908"),
        surfaceElevated: Color(hex: "160C0A"),
        surfaceInset:    Color(hex: "040202"),
        textPrimary:     Color(hex: "F0F0F0"),
        textSecondary:   Color(hex: "888888"),
        textMuted:       Color(hex: "505050"),
        separator:       Color(hex: "FF1E1E").opacity(0.08),
        separatorSubtle: Color(hex: "FF1E1E").opacity(0.04),
        separatorStrong: Color(hex: "FF1E1E").opacity(0.18),
        danger:          Color(hex: "FF5500"),
        success:         Color(hex: "32D74B"),
        warning:         Color(hex: "FFD60A"),
        info:            Color(hex: "64D2FF"),
        cardCornerRadius: 4,
        cardBorderWidth:  1.0,
        cardBorderColor:  Color(hex: "FF1E1E").opacity(0.22),
        cardShadowColor:  Color(hex: "FF1E1E").opacity(0.20),
        cardShadowRadius: 6,
        cardShadowOffset: CGSize(width: 0, height: 3),
        cardGlowColor:    .clear,
        cardGlowRadius:   0,
        chartPalette:          [Color(hex: "FF1E1E"), Color(hex: "FF5555"), Color(hex: "CC0000"),
                                Color(hex: "FF8080"), Color(hex: "880000")],
        glassOpacity:          0.06,
        accentGradientColors:  [Color(hex: "FF1E1E"), Color(hex: "8B0000")]
    )

    static let blood = AppThemeColors(
        accent:          Color(hex: "C0392B"),
        accentLight:     Color(hex: "E74C3C"),
        accentMuted:     Color(hex: "2D0A08"),
        onAccent:        .white,
        background:      Color(hex: "120808"),
        surfaceCard:     Color(hex: "1C1008"),
        surfaceElevated: Color(hex: "281408"),
        surfaceInset:    Color(hex: "0F0606"),
        textPrimary:     Color(hex: "FFF0E8"),
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
        cardGlowColor:    Color(hex: "C0392B").opacity(0.12),
        cardGlowRadius:   16,
        chartPalette:          [Color(hex: "E74C3C"), Color(hex: "F39C12"), Color(hex: "27AE60"),
                                Color(hex: "2980B9"), Color(hex: "8E44AD")],
        glassOpacity:          0.15,
        accentGradientColors:  [Color(hex: "E74C3C"), Color(hex: "7B241C")]
    )

    // Vert forêt — teinte fond exclusive, distinct du phosphore pur de Matrix.
    static let electric = AppThemeColors(
        accent:          Color(hex: "E8FF00"),
        accentLight:     Color(hex: "F4FF66"),
        accentMuted:     Color(hex: "1E2000"),
        onAccent:        .black,
        background:      Color(hex: "040C04"),
        surfaceCard:     Color(hex: "0A120A"),
        surfaceElevated: Color(hex: "101A10"),
        surfaceInset:    Color(hex: "060E06"),
        textPrimary:     Color(hex: "F0FFF0"),
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
        chartPalette:          [Color(hex: "E8FF00"), Color(hex: "00CFFF"), Color(hex: "FF6B2B"),
                                Color(hex: "C77DFF"), Color(hex: "FF3860")],
        glassOpacity:          0.20,
        accentGradientColors:  [Color(hex: "E8FF00"), Color(hex: "B8CC00")]
    )

    // Phosphore vert pur froid — canal G seul, distinct du vert forêt d'Electric.
    // textPrimary = vert phosphore : l'app devient la console.
    static let matrix = AppThemeColors(
        accent:          Color(hex: "00FF66"),
        accentLight:     Color(hex: "66FFB2"),
        accentMuted:     Color(hex: "003311"),
        onAccent:        Color(hex: "001600"),
        background:      Color(hex: "001600"),
        surfaceCard:     Color(hex: "0A1A0A"),
        surfaceElevated: Color(hex: "142814"),
        surfaceInset:    Color(hex: "000E00"),
        textPrimary:     Color(hex: "00FF66"),
        textSecondary:   Color(hex: "00994D"),
        textMuted:       Color(hex: "004422"),
        separator:       Color(hex: "00FF66").opacity(0.08),
        separatorSubtle: Color(hex: "00FF66").opacity(0.04),
        separatorStrong: Color(hex: "00FF66").opacity(0.16),
        danger:          Color(hex: "FF453A"),
        success:         Color(hex: "00FF66"),
        warning:         Color(hex: "FFFF00"),
        info:            Color(hex: "00CFFF"),
        cardCornerRadius: 6,
        cardBorderWidth:  1.0,
        cardBorderColor:  Color(hex: "00FF66").opacity(0.18),
        cardShadowColor:  Color(hex: "00FF66").opacity(0.10),
        cardShadowRadius: 8,
        cardShadowOffset: CGSize(width: 0, height: 2),
        cardGlowColor:    Color(hex: "00FF66").opacity(0.12),
        cardGlowRadius:   16,
        chartPalette:          [Color(hex: "00FF66"), Color(hex: "00CFFF"), Color(hex: "FFFF00"),
                                Color(hex: "FF6B2B"), Color(hex: "CC00FF")],
        glassOpacity:          0.15,
        accentGradientColors:  [Color(hex: "00FF66"), Color(hex: "007733")]
    )

    // Nuit violet-bleu — décalé vers le violet pour quitter le territoire bleu d'Arctic.
    static let tokyo = AppThemeColors(
        accent:          Color(hex: "8B5CF6"),
        accentLight:     Color(hex: "FF6B9E"),
        accentMuted:     Color(hex: "2D1660"),
        onAccent:        .white,
        background:      Color(hex: "0E0B20"),
        surfaceCard:     Color(hex: "16123A"),
        surfaceElevated: Color(hex: "1E1A4A"),
        surfaceInset:    Color(hex: "0A0816"),
        textPrimary:     Color(hex: "F0E8FF"),
        textSecondary:   Color(hex: "9B8FC0"),
        textMuted:       Color(hex: "554870"),
        separator:       Color(hex: "8B5CF6").opacity(0.08),
        separatorSubtle: Color(hex: "8B5CF6").opacity(0.04),
        separatorStrong: Color(hex: "8B5CF6").opacity(0.16),
        danger:          Color(hex: "FF453A"),
        success:         Color(hex: "34C759"),
        warning:         Color(hex: "FFD60A"),
        info:            Color(hex: "00D4FF"),
        cardCornerRadius: 16,
        cardBorderWidth:  1.0,
        cardBorderColor:  Color(hex: "8B5CF6").opacity(0.20),
        cardShadowColor:  Color(hex: "8B5CF6").opacity(0.12),
        cardShadowRadius: 12,
        cardShadowOffset: CGSize(width: 0, height: 4),
        cardGlowColor:    Color(hex: "8B5CF6").opacity(0.15),
        cardGlowRadius:   20,
        chartPalette:          [Color(hex: "8B5CF6"), Color(hex: "FF6B9E"), Color(hex: "00D4FF"),
                                Color(hex: "F59E0B"), Color(hex: "34C759")],
        glassOpacity:          0.18,
        accentGradientColors:  [Color(hex: "8B5CF6"), Color(hex: "FF6B9E")]
    )

    // Océan teal-bleu — absorbe Arctic existant + palette Deep Ocean.
    static let arctic = AppThemeColors(
        accent:          Color(hex: "7DD3FC"),
        accentLight:     Color(hex: "BAE6FD"),
        accentMuted:     Color(hex: "0C2D42"),
        onAccent:        Color(hex: "07131F"),
        background:      Color(hex: "07131F"),
        surfaceCard:     Color(hex: "0D1E30"),
        surfaceElevated: Color(hex: "12253A"),
        surfaceInset:    Color(hex: "050E17"),
        textPrimary:     Color(hex: "DFF6FF"),
        textSecondary:   Color(hex: "7BB8D0"),
        textMuted:       Color(hex: "3A6680"),
        separator:       Color(hex: "7DD3FC").opacity(0.08),
        separatorSubtle: Color(hex: "7DD3FC").opacity(0.04),
        separatorStrong: Color(hex: "7DD3FC").opacity(0.16),
        danger:          Color(hex: "FF453A"),
        success:         Color(hex: "34C759"),
        warning:         Color(hex: "FFD60A"),
        info:            Color(hex: "7DD3FC"),
        cardCornerRadius: 12,
        cardBorderWidth:  1.0,
        cardBorderColor:  Color(hex: "7DD3FC").opacity(0.20),
        cardShadowColor:  Color(hex: "7DD3FC").opacity(0.10),
        cardShadowRadius: 12,
        cardShadowOffset: CGSize(width: 0, height: 4),
        cardGlowColor:    Color(hex: "7DD3FC").opacity(0.12),
        cardGlowRadius:   16,
        chartPalette:          [Color(hex: "7DD3FC"), Color(hex: "0066FF"), Color(hex: "00C2FF"),
                                Color(hex: "BAE6FD"), Color(hex: "0891B2")],
        glassOpacity:          0.15,
        accentGradientColors:  [Color(hex: "7DD3FC"), Color(hex: "0066FF")]
    )

    // Rolex, lounge privé. L'or présent mais qui ne crie jamais.
    static let goldNoir = AppThemeColors(
        accent:          Color(hex: "D4AF37"),
        accentLight:     Color(hex: "FFF7D6"),
        accentMuted:     Color(hex: "2A1C05"),
        onAccent:        Color(hex: "0B0905"),
        background:      Color(hex: "0B0905"),
        surfaceCard:     Color(hex: "14110A"),
        surfaceElevated: Color(hex: "1C1810"),
        surfaceInset:    Color(hex: "080603"),
        textPrimary:     Color(hex: "FFF7D6"),
        textSecondary:   Color(hex: "C4A959"),
        textMuted:       Color(hex: "7A6840"),
        separator:       Color(hex: "D4AF37").opacity(0.08),
        separatorSubtle: Color(hex: "D4AF37").opacity(0.04),
        separatorStrong: Color(hex: "D4AF37").opacity(0.14),
        danger:          Color(hex: "FF453A"),
        success:         Color(hex: "32D74B"),
        warning:         Color(hex: "FF9F0A"),
        info:            Color(hex: "64D2FF"),
        cardCornerRadius: 10,
        cardBorderWidth:  1.0,
        cardBorderColor:  Color(hex: "D4AF37").opacity(0.18),
        cardShadowColor:  Color(hex: "D4AF37").opacity(0.10),
        cardShadowRadius: 8,
        cardShadowOffset: CGSize(width: 0, height: 2),
        cardGlowColor:    .clear,
        cardGlowRadius:   0,
        chartPalette:          [Color(hex: "D4AF37"), Color(hex: "FFF7D6"), Color(hex: "B8860B"),
                                Color(hex: "8B6914"), Color(hex: "C4A959")],
        glassOpacity:          0.10,
        accentGradientColors:  [Color(hex: "D4AF37"), Color(hex: "B8860B")]
    )

    // Dune, Sahara. Fond le plus clair du catalogue — stress test inverse.
    static let desert = AppThemeColors(
        accent:          Color(hex: "E9C46A"),
        accentLight:     Color(hex: "F4D08A"),
        accentMuted:     Color(hex: "4A2C08"),
        onAccent:        Color(hex: "2C1810"),
        background:      Color(hex: "2C1810"),
        surfaceCard:     Color(hex: "3A2218"),
        surfaceElevated: Color(hex: "4A2C20"),
        surfaceInset:    Color(hex: "221408"),
        textPrimary:     Color(hex: "FFF0DC"),
        textSecondary:   Color(hex: "C49A6C"),
        textMuted:       Color(hex: "7A6050"),
        separator:       Color(hex: "D4A373").opacity(0.12),
        separatorSubtle: Color(hex: "D4A373").opacity(0.06),
        separatorStrong: Color(hex: "D4A373").opacity(0.22),
        danger:          Color(hex: "FF453A"),
        success:         Color(hex: "32D74B"),
        warning:         Color(hex: "FFD60A"),
        info:            Color(hex: "64D2FF"),
        cardCornerRadius: 12,
        cardBorderWidth:  1.0,
        cardBorderColor:  Color(hex: "D4A373").opacity(0.18),
        cardShadowColor:  Color(hex: "000000").opacity(0.20),
        cardShadowRadius: 10,
        cardShadowOffset: CGSize(width: 0, height: 3),
        cardGlowColor:    Color(hex: "E9C46A").opacity(0.08),
        cardGlowRadius:   12,
        chartPalette:          [Color(hex: "E9C46A"), Color(hex: "D4A373"), Color(hex: "F4A261"),
                                Color(hex: "264653"), Color(hex: "2A9D8F")],
        glassOpacity:          0.12,
        accentGradientColors:  [Color(hex: "E9C46A"), Color(hex: "D4A373")]
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
        case .sinCity:    return .sinCity
        case .blood:      return .blood
        case .electric:   return .electric
        case .matrix:     return .matrix
        case .tokyo:      return .tokyo
        case .arctic:     return .arctic
        case .goldNoir:   return .goldNoir
        case .desert:     return .desert
        }
    }

    // Raccourcis directs
    var accent:          Color { colors.accent }
    var accentLight:     Color { colors.accentLight }
    var accentMuted:     Color { colors.accentMuted }
    var onAccent:        Color { colors.onAccent }

    var background:      Color { colors.background }
    var surfaceCard:     Color { colors.surfaceCard }
    var surfaceElevated: Color { colors.surfaceElevated }
    var surfaceInset:    Color { colors.surfaceInset }

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

    var glassOpacity: Double { colors.glassOpacity }

    // Palette graphiques — accès par index cyclé
    var chartPalette: [Color] { colors.chartPalette }
    func chartColor(_ index: Int) -> Color { chartPalette[index % chartPalette.count] }

    func accentGradient(startPoint: UnitPoint = .leading, endPoint: UnitPoint = .trailing) -> LinearGradient {
        LinearGradient(colors: colors.accentGradientColors, startPoint: startPoint, endPoint: endPoint)
    }
}
