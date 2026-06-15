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

// MARK: - Card Style

enum CardStyle {
    case flat       // border only, no shadow, no glow  (Monochrome, Sin City)
    case outlined   // thick border, no shadow, no glow (Matrix)
    case floating   // border + glow + shadow           (Blood, Electric, Tokyo, Arctic)
    case raised     // border + shadow, no glow         (Gold Noir, Desert)
}

// MARK: - Accent Distribution

enum AccentDistribution {
    case pervasive  // accent sur toutes les surfaces structurelles
    case surgical   // accent réservé aux foregrounds explicites uniquement
}

// MARK: - Identity Layer Style

enum IdentityLayerStyle {
    case none
    case scanlines(opacity: Double)
    case neonHalo(color: Color, intensity: Double)
    case filmGrain(opacity: Double)
    case goldFiligree(opacity: Double)
    case cyberGrid(opacity: Double)
    case arcticFrost(opacity: Double)
    case bloodVein(opacity: Double)
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
    let identityLayer:        IdentityLayerStyle

    // Typographie par thème — appHero & appTitle lisent ces tokens au re-render
    let heroFontDesign:  Font.Design
    let titleFontDesign: Font.Design
    let displayWeight:   Font.Weight

    // Opacité du fond accentué sur les cards primaires (GlassCardAccent)
    let cardAccentFillOpacity: Double

    // Opacité du stroke accent sur les cards primaires (GlassCardAccent) — 0.25 standard, réduit pour les thèmes discrets
    let cardAccentStrokeOpacity: Double

    // Style structurel des cards — levier visuel principal de différenciation entre thèmes
    let cardStyle: CardStyle
    let accentDistribution: AccentDistribution

    // Taille de base des métriques hero dans les cartes Dashboard
    // appCardHero = heroNumberSize, appCardMetric = heroNumberSize - 6
    let heroNumberSize: CGFloat

    // Typographie des titres de sections (SectionLabel)
    let sectionTitleTracking:   CGFloat
    let sectionTitleUppercased: Bool
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
        cardCornerRadius: 4,
        cardBorderWidth:  0.5,
        cardBorderColor:  Color.white.opacity(0.12),
        cardShadowColor:  .clear,
        cardShadowRadius: 0,
        cardShadowOffset: CGSize(width: 0, height: 0),
        cardGlowColor:    .clear,
        cardGlowRadius:   0,
        chartPalette:          [.white, Color.white.opacity(0.65), Color.white.opacity(0.45),
                                Color.white.opacity(0.30), Color.white.opacity(0.18)],
        glassOpacity:          0.10,
        accentGradientColors:  [.white, Color(hex: "A0A0A0")],
        identityLayer:         .none,
        heroFontDesign:        .default,
        titleFontDesign:       .default,
        displayWeight:         .thin,
        cardAccentFillOpacity:   0.04,
        cardAccentStrokeOpacity: 0.25,
        cardStyle:               .flat,
        accentDistribution:      .pervasive,
        heroNumberSize:        36,
        sectionTitleTracking:  2.0,
        sectionTitleUppercased: true
    )

    // Film noir, détective. Tout est noir et blanc sauf le sang.
    // accentDistribution: .surgical — le rouge #FF1E1E ne touche AUCUNE surface structurelle.
    // Séparateurs/bordures/fills = blanc@opacity. Le rouge sort uniquement en foreground explicite.
    static let sinCity = AppThemeColors(
        accent:          Color(hex: "FF1E1E"),
        accentLight:     Color(hex: "FF5555"),
        accentMuted:     Color(hex: "1A0000"),
        onAccent:        Color(hex: "F0F0F0"),
        background:      Color(hex: "060403"),
        surfaceCard:     Color(hex: "0E0908"),
        surfaceElevated: Color(hex: "160C0A"),
        surfaceInset:    Color(hex: "040202"),
        textPrimary:     .white,
        textSecondary:   Color.white.opacity(0.45),
        textMuted:       Color.white.opacity(0.22),
        separator:       Color.white.opacity(0.06),
        separatorSubtle: Color.white.opacity(0.03),
        separatorStrong: Color.white.opacity(0.10),
        danger:          Color(hex: "FF5500"),
        success:         Color(hex: "32D74B"),
        warning:         Color(hex: "FFD60A"),
        info:            Color(hex: "64D2FF"),
        cardCornerRadius: 2,
        cardBorderWidth:  0.5,
        cardBorderColor:  Color.white.opacity(0.08),
        cardShadowColor:  .clear,
        cardShadowRadius: 0,
        cardShadowOffset: .zero,
        cardGlowColor:    .clear,
        cardGlowRadius:   0,
        chartPalette:          [.white, Color(white: 0.75), Color(white: 0.55),
                                Color(white: 0.38), Color(white: 0.22)],
        glassOpacity:          0.06,
        accentGradientColors:  [.white, Color(hex: "C0C0C0")],
        identityLayer:         .filmGrain(opacity: 0.035),
        heroFontDesign:        .default,
        titleFontDesign:       .default,
        displayWeight:         .black,
        cardAccentFillOpacity:   0.0,
        cardAccentStrokeOpacity: 0.0,
        cardStyle:               .flat,
        accentDistribution:      .surgical,
        heroNumberSize:        42,
        sectionTitleTracking:  1.5,
        sectionTitleUppercased: true
    )

    // Rouge profond assumé — fond L*≈8, visiblement rouge sur device (vs L*≈2.8 avant)
    static let blood = AppThemeColors(
        accent:          Color(hex: "C0392B"),
        accentLight:     Color(hex: "E74C3C"),
        accentMuted:     Color(hex: "4A1010"),
        onAccent:        .white,
        background:      Color(hex: "3D0C0C"),
        surfaceCard:     Color(hex: "4D1212"),
        surfaceElevated: Color(hex: "5A1616"),
        surfaceInset:    Color(hex: "300808"),
        textPrimary:     Color(hex: "FFF0E8"),
        textSecondary:   Color(hex: "AAAAAA"),
        textMuted:       Color(hex: "888888"),
        separator:       Color(hex: "C0392B").opacity(0.20),
        separatorSubtle: Color(hex: "C0392B").opacity(0.10),
        separatorStrong: Color(hex: "C0392B").opacity(0.35),
        danger:          Color(hex: "FF453A"),
        success:         Color(hex: "2ECC71"),
        warning:         Color(hex: "F39C12"),
        info:            Color(hex: "64D2FF"),
        cardCornerRadius: 22,
        cardBorderWidth:  1.0,
        cardBorderColor:  Color(hex: "C0392B").opacity(0.30),
        cardShadowColor:  Color(hex: "1A0404").opacity(0.55),
        cardShadowRadius: 20,
        cardShadowOffset: CGSize(width: 0, height: 5),
        cardGlowColor:    Color(hex: "C0392B").opacity(0.22),
        cardGlowRadius:   20,
        chartPalette:          [Color(hex: "E74C3C"), Color(hex: "F39C12"), Color(hex: "27AE60"),
                                Color(hex: "2980B9"), Color(hex: "8E44AD")],
        glassOpacity:          0.15,
        accentGradientColors:  [Color(hex: "E74C3C"), Color(hex: "7B241C")],
        identityLayer:         .bloodVein(opacity: 0.07),
        heroFontDesign:        .rounded,
        titleFontDesign:       .rounded,
        displayWeight:         .heavy,
        cardAccentFillOpacity:   0.08,
        cardAccentStrokeOpacity: 0.25,
        cardStyle:               .floating,
        accentDistribution:      .pervasive,
        heroNumberSize:          44,
        sectionTitleTracking:    0.8,
        sectionTitleUppercased: false
    )

    // Jaune électrique pur — fond chargé jaune-noir, jaune qui inonde toutes les surfaces.
    // accentDistribution: .pervasive — le jaune #FFFF33 baigne l'interface via fills élevés.
    static let electric = AppThemeColors(
        accent:          Color(hex: "FFFF33"),
        accentLight:     Color(hex: "FFFF80"),
        accentMuted:     Color(hex: "1F1F00"),
        onAccent:        .black,
        background:      Color(hex: "0F1000"),
        surfaceCard:     Color(hex: "1A1C00"),
        surfaceElevated: Color(hex: "222400"),
        surfaceInset:    Color(hex: "0A0B00"),
        textPrimary:     Color(hex: "F5FFB0"),
        textSecondary:   Color(hex: "B8C800"),
        textMuted:       Color(hex: "4A5000"),
        separator:       Color(hex: "FFFF33").opacity(0.15),
        separatorSubtle: Color(hex: "FFFF33").opacity(0.08),
        separatorStrong: Color(hex: "FFFF33").opacity(0.30),
        danger:          Color(hex: "FF3B30"),
        success:         Color(hex: "00E5FF"),
        warning:         Color(hex: "FF9F0A"),
        info:            Color(hex: "38BDF8"),
        cardCornerRadius: 18,
        cardBorderWidth:  1.5,
        cardBorderColor:  Color(hex: "FFFF33").opacity(0.45),
        cardShadowColor:  Color(hex: "FFFF33").opacity(0.35),
        cardShadowRadius: 12,
        cardShadowOffset: CGSize(width: 0, height: 4),
        cardGlowColor:    Color(hex: "FFFF33").opacity(0.55),
        cardGlowRadius:   35,
        chartPalette:          [Color(hex: "FFFF33"), Color(hex: "00CFFF"), Color(hex: "FF6B2B"),
                                Color(hex: "C77DFF"), Color(hex: "FF3860")],
        glassOpacity:          0.35,
        accentGradientColors:  [Color(hex: "FFFF33"), Color(hex: "CCDD00")],
        identityLayer:         .cyberGrid(opacity: 0.08),
        heroFontDesign:        .monospaced,
        titleFontDesign:       .default,
        displayWeight:         .semibold,
        cardAccentFillOpacity:   0.42,
        cardAccentStrokeOpacity: 0.65,
        cardStyle:               .floating,
        accentDistribution:      .pervasive,
        heroNumberSize:          40,
        sectionTitleTracking:    2.0,
        sectionTitleUppercased: true
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
        cardCornerRadius: 0,
        cardBorderWidth:  2.0,
        cardBorderColor:  Color(hex: "00FF66").opacity(0.30),
        cardShadowColor:  Color(hex: "00FF66").opacity(0.10),
        cardShadowRadius: 8,
        cardShadowOffset: CGSize(width: 0, height: 2),
        cardGlowColor:    Color(hex: "00FF66").opacity(0.12),
        cardGlowRadius:   16,
        chartPalette:          [Color(hex: "00FF66"), Color(hex: "00CFFF"), Color(hex: "FFFF00"),
                                Color(hex: "FF6B2B"), Color(hex: "CC00FF")],
        glassOpacity:          0.15,
        accentGradientColors:  [Color(hex: "00FF66"), Color(hex: "007733")],
        identityLayer:         .scanlines(opacity: 0.04),
        heroFontDesign:        .monospaced,
        titleFontDesign:       .monospaced,
        displayWeight:         .medium,
        cardAccentFillOpacity:   0.12,
        cardAccentStrokeOpacity: 0.25,
        cardStyle:               .outlined,
        accentDistribution:      .pervasive,
        heroNumberSize:        38,
        sectionTitleTracking:  2.5,
        sectionTitleUppercased: true
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
        cardCornerRadius: 28,
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
        accentGradientColors:  [Color(hex: "8B5CF6"), Color(hex: "FF6B9E")],
        identityLayer:         .neonHalo(color: Color(hex: "FF6B9E"), intensity: 0.18),
        heroFontDesign:        .rounded,
        titleFontDesign:       .rounded,
        displayWeight:         .bold,
        cardAccentFillOpacity:   0.10,
        cardAccentStrokeOpacity: 0.25,
        cardStyle:               .floating,
        accentDistribution:      .pervasive,
        heroNumberSize:          44,
        sectionTitleTracking:    0.3,
        sectionTitleUppercased: false
    )

    // Océan teal-bleu — fond L*≈20 (#1A3A5C), visiblement bleu profond sur device.
    static let arctic = AppThemeColors(
        accent:          Color(hex: "7DD3FC"),
        accentLight:     Color(hex: "BAE6FD"),
        accentMuted:     Color(hex: "0C2D42"),
        onAccent:        Color(hex: "07131F"),
        background:      Color(hex: "1A3A5C"),
        surfaceCard:     Color(hex: "1E4570"),
        surfaceElevated: Color(hex: "22527C"),
        surfaceInset:    Color(hex: "142D48"),
        textPrimary:     Color(hex: "DFF6FF"),
        textSecondary:   Color(hex: "7BB8D0"),
        textMuted:       Color(hex: "6BA8C4"),
        separator:       Color(hex: "7DD3FC").opacity(0.15),
        separatorSubtle: Color(hex: "7DD3FC").opacity(0.08),
        separatorStrong: Color(hex: "7DD3FC").opacity(0.28),
        danger:          Color(hex: "FF453A"),
        success:         Color(hex: "34C759"),
        warning:         Color(hex: "FFD60A"),
        info:            Color(hex: "7DD3FC"),
        cardCornerRadius: 20,
        cardBorderWidth:  1.0,
        cardBorderColor:  Color(hex: "7DD3FC").opacity(0.32),
        cardShadowColor:  Color(hex: "091D30").opacity(0.55),
        cardShadowRadius: 18,
        cardShadowOffset: CGSize(width: 0, height: 6),
        cardGlowColor:    Color(hex: "7DD3FC").opacity(0.20),
        cardGlowRadius:   22,
        chartPalette:          [Color(hex: "7DD3FC"), Color(hex: "0066FF"), Color(hex: "00C2FF"),
                                Color(hex: "BAE6FD"), Color(hex: "0891B2")],
        glassOpacity:          0.15,
        accentGradientColors:  [Color(hex: "7DD3FC"), Color(hex: "0066FF")],
        identityLayer:         .arcticFrost(opacity: 0.08),
        heroFontDesign:        .rounded,
        titleFontDesign:       .rounded,
        displayWeight:         .light,
        cardAccentFillOpacity:   0.10,
        cardAccentStrokeOpacity: 0.25,
        cardStyle:               .floating,
        accentDistribution:      .pervasive,
        heroNumberSize:          40,
        sectionTitleTracking:    1.2,
        sectionTitleUppercased: false
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
        cardCornerRadius: 12,
        cardBorderWidth:  1.5,
        cardBorderColor:  Color(hex: "D4AF37").opacity(0.18),
        cardShadowColor:  Color(hex: "D4AF37").opacity(0.10),
        cardShadowRadius: 8,
        cardShadowOffset: CGSize(width: 0, height: 2),
        cardGlowColor:    .clear,
        cardGlowRadius:   0,
        chartPalette:          [Color(hex: "D4AF37"), Color(hex: "FFF7D6"), Color(hex: "B8860B"),
                                Color(hex: "8B6914"), Color(hex: "C4A959")],
        glassOpacity:          0.10,
        accentGradientColors:  [Color(hex: "D4AF37"), Color(hex: "B8860B")],
        identityLayer:         .goldFiligree(opacity: 0.06),
        heroFontDesign:        .serif,
        titleFontDesign:       .serif,
        displayWeight:         .semibold,
        cardAccentFillOpacity:   0.07,
        cardAccentStrokeOpacity: 0.16,
        cardStyle:               .raised,
        accentDistribution:      .pervasive,
        heroNumberSize:        36,
        sectionTitleTracking:  1.8,
        sectionTitleUppercased: true
    )

    // Dune, Sahara. Fond L*≈22 (#5C3D2E), chaleur sable visible — le plus clair du catalogue.
    static let desert = AppThemeColors(
        accent:          Color(hex: "E9C46A"),
        accentLight:     Color(hex: "F4D08A"),
        accentMuted:     Color(hex: "4A2C08"),
        onAccent:        Color(hex: "2C1810"),
        background:      Color(hex: "5C3D2E"),
        surfaceCard:     Color(hex: "6B4A38"),
        surfaceElevated: Color(hex: "7A5542"),
        surfaceInset:    Color(hex: "4A3020"),
        textPrimary:     Color(hex: "FFF0DC"),
        textSecondary:   Color(hex: "C49A6C"),
        textMuted:       Color(hex: "B08070"),
        separator:       Color(hex: "D4A373").opacity(0.18),
        separatorSubtle: Color(hex: "D4A373").opacity(0.10),
        separatorStrong: Color(hex: "D4A373").opacity(0.32),
        danger:          Color(hex: "FF453A"),
        success:         Color(hex: "32D74B"),
        warning:         Color(hex: "FFD60A"),
        info:            Color(hex: "64D2FF"),
        cardCornerRadius: 16,
        cardBorderWidth:  0.5,
        cardBorderColor:  Color(hex: "D4A373").opacity(0.28),
        cardShadowColor:  Color(hex: "2A1208").opacity(0.55),
        cardShadowRadius: 14,
        cardShadowOffset: CGSize(width: 0, height: 5),
        cardGlowColor:    Color(hex: "E9C46A").opacity(0.14),
        cardGlowRadius:   12,
        chartPalette:          [Color(hex: "E9C46A"), Color(hex: "D4A373"), Color(hex: "F4A261"),
                                Color(hex: "264653"), Color(hex: "2A9D8F")],
        glassOpacity:          0.12,
        accentGradientColors:  [Color(hex: "E9C46A"), Color(hex: "D4A373")],
        identityLayer:         .none,
        heroFontDesign:        .default,
        titleFontDesign:       .default,
        displayWeight:         .medium,
        cardAccentFillOpacity:   0.09,
        cardAccentStrokeOpacity: 0.25,
        cardStyle:               .raised,
        accentDistribution:      .pervasive,
        heroNumberSize:        40,
        sectionTitleTracking:  0.5,
        sectionTitleUppercased: false
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
    var accent:      Color { colors.accentDistribution == .surgical ? .white              : colors.accent }
    var accentLight: Color { colors.accentDistribution == .surgical ? .white.opacity(0.7) : colors.accentLight }
    var accentMuted:     Color { colors.accentMuted }
    var onAccent:        Color { colors.accentDistribution == .surgical ? .black : colors.onAccent }

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
    var danger:  Color { colors.accentDistribution == .surgical ? Color(white: 0.72) : colors.danger  }
    var success: Color { colors.accentDistribution == .surgical ? Color(white: 0.68) : colors.success }
    var warning: Color { colors.accentDistribution == .surgical ? Color(white: 0.55) : colors.warning }
    var info:    Color { colors.accentDistribution == .surgical ? Color(white: 0.50) : colors.info    }

    var cardCornerRadius: CGFloat { colors.cardCornerRadius }
    var cardBorderWidth:  CGFloat { colors.cardBorderWidth }
    var cardBorderColor:  Color   { colors.cardBorderColor }
    var cardShadowColor:  Color   { colors.cardShadowColor }
    var cardShadowRadius: CGFloat { colors.cardShadowRadius }
    var cardShadowOffset: CGSize  { colors.cardShadowOffset }
    var cardGlowColor:    Color   { colors.cardGlowColor }
    var cardGlowRadius:   CGFloat { colors.cardGlowRadius }

    var glassOpacity:    Double             { colors.glassOpacity }
    var identityLayer:   IdentityLayerStyle { colors.identityLayer }
    var cardStyle:       CardStyle          { colors.cardStyle }
    var heroNumberSize:          CGFloat { colors.heroNumberSize }
    var sectionTitleTracking:   CGFloat { colors.sectionTitleTracking }
    var sectionTitleUppercased: Bool    { colors.sectionTitleUppercased }
    var heroFontDesign:          Font.Design { colors.heroFontDesign }
    var titleFontDesign:         Font.Design { colors.titleFontDesign }
    var displayWeight:           Font.Weight { colors.displayWeight }
    var cardAccentFillOpacity:   Double      { colors.cardAccentFillOpacity }

    // Palette graphiques — accès par index cyclé
    var chartPalette: [Color] { colors.chartPalette }
    func chartColor(_ index: Int) -> Color { chartPalette[index % chartPalette.count] }

    func accentGradient(startPoint: UnitPoint = .leading, endPoint: UnitPoint = .trailing) -> LinearGradient {
        LinearGradient(colors: colors.accentGradientColors, startPoint: startPoint, endPoint: endPoint)
    }
}
