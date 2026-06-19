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
    case goldNoir      = "goldNoir"
    case desert        = "desert"
    case electricLight = "electricLight"

    var displayName: String {
        switch self {
        case .monochrome:    return "Monochrome"
        case .sinCity:       return "Sin City"
        case .blood:         return "Blood"
        case .electric:      return "Electric"
        case .matrix:        return "Matrix"
        case .tokyo:         return "Tokyo"
        case .arctic:        return "Arctic Frost"
        case .goldNoir:      return "Gold Noir"
        case .desert:        return "Desert"
        case .electricLight: return "Electric Light"
        }
    }

    var previewColor: Color {
        switch self {
        case .monochrome:    return Color(hex: "1C1C1E")
        case .sinCity:       return Color(hex: "FF1E1E")
        case .blood:         return Color(hex: "C0392B")
        case .electric:      return Color(hex: "E8FF00")
        case .matrix:        return Color(hex: "00FF66")
        case .tokyo:         return Color(hex: "8B5CF6")
        case .arctic:        return Color(hex: "7DD3FC")
        case .goldNoir:      return Color(hex: "D4AF37")
        case .desert:        return Color(hex: "E9C46A")
        case .electricLight: return Color(hex: "FFFF33")
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
    let onBackground:    Color   // texte sur le fond (diverge d'onSurface uniquement en Electric Light)
    let onSurface:       Color   // texte sur les cards
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

    // Le Refus. Noir absolu, blanc chirurgical — les surfaces n'ont pas de couleur, seule l'info existe.
    // accentDistribution: .surgical — le blanc n'apparaît qu'en foreground explicite.
    // cardStyle: .flat sans shadow → la bordure white@0.12/0.5px est le seul délimiteur. Ne pas toucher.
    static let monochrome = AppThemeColors(
        accent:          .white,
        accentLight:     Color(hex: "AEAEB2"),
        accentMuted:     Color(hex: "F2F2F7"),
        onAccent:        .black,
        background:      .black,
        surfaceCard:     Color(hex: "2A2A2E"),
        surfaceElevated: Color(hex: "2C2C2E"),
        surfaceInset:    Color(hex: "0D0D0F"),
        textPrimary:     .white,
        onBackground:    .white,
        onSurface:       .white,
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
        identityLayer:         .scanlines(opacity: 0.04),  // 0.02 imperceptible ; 0.04 = grain monacal
        heroFontDesign:        .default,
        titleFontDesign:       .default,
        displayWeight:         .thin,
        cardAccentFillOpacity:   0.0,   // surgical — surfaces sans couleur
        cardAccentStrokeOpacity: 0.0,   // surgical — stroke overlay supprimé
        cardStyle:               .flat,
        accentDistribution:      .surgical,
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
        surfaceCard:     Color(hex: "1A1410"),
        surfaceElevated: Color(hex: "160C0A"),
        surfaceInset:    Color(hex: "040202"),
        textPrimary:     .white,
        onBackground:    .white,
        onSurface:       .white,
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
        identityLayer:         .filmGrain(opacity: 0.05),
        heroFontDesign:        .default,
        titleFontDesign:       .serif,
        displayWeight:         .black,
        cardAccentFillOpacity:   0.0,
        cardAccentStrokeOpacity: 0.0,
        cardStyle:               .flat,
        accentDistribution:      .surgical,
        heroNumberSize:        42,
        sectionTitleTracking:  1.5,
        sectionTitleUppercased: true
    )

    // La Matière / La Blessure. Vous êtes à l'intérieur — immergé, pas spectateur.
    // textSecondary/Muted teinté dans le monde rouge (plus de gris neutres qui brisent l'immersion).
    // Glow drastiquement réduit — le sang séché ne pulse pas.
    static let blood = AppThemeColors(
        accent:          Color(hex: "C0392B"),
        accentLight:     Color(hex: "E74C3C"),
        accentMuted:     Color(hex: "4A1010"),
        onAccent:        .white,
        background:      Color(hex: "3D0C0C"),
        surfaceCard:     Color(hex: "5A1818"),
        surfaceElevated: Color(hex: "5A1616"),
        surfaceInset:    Color(hex: "300808"),
        textPrimary:     Color(hex: "FFF0E8"),
        onBackground:    Color(hex: "FFF0E8"),
        onSurface:       Color(hex: "FFF0E8"),
        textSecondary:   Color(hex: "D09090"),  // rose-rouge atténué — reste dans le monde
        textMuted:       Color(hex: "7A5252"),  // brun-rouge sombre — muet mais teinté
        separator:       Color(hex: "C0392B").opacity(0.20),
        separatorSubtle: Color(hex: "C0392B").opacity(0.10),
        separatorStrong: Color(hex: "C0392B").opacity(0.35),
        danger:          Color(hex: "FF453A"),
        success:         Color(hex: "2ECC71"),
        warning:         Color(hex: "F39C12"),
        info:            Color(hex: "64D2FF"),
        cardCornerRadius: 12,                            // moins pill-shaped — dureté viscérale
        cardBorderWidth:  1.0,
        cardBorderColor:  Color(hex: "C0392B").opacity(0.30),
        cardShadowColor:  Color(hex: "1A0404").opacity(0.55),
        cardShadowRadius: 20,
        cardShadowOffset: CGSize(width: 0, height: 5),
        cardGlowColor:    Color(hex: "C0392B").opacity(0.08), // chaleur ambiante, pas halo pulsant
        cardGlowRadius:   12,
        chartPalette:          [Color(hex: "E74C3C"), Color(hex: "F39C12"), Color(hex: "27AE60"),
                                Color(hex: "2980B9"), Color(hex: "8E44AD")],
        glassOpacity:          0.15,
        accentGradientColors:  [Color(hex: "E74C3C"), Color(hex: "7B241C")],
        identityLayer:         .bloodVein(opacity: 0.07),
        heroFontDesign:        .default,                 // organique/lourd, pas chaleureux/sportif
        titleFontDesign:       .default,
        displayWeight:         .heavy,
        cardAccentFillOpacity:   0.14,
        cardAccentStrokeOpacity: 0.25,
        cardStyle:               .floating,
        accentDistribution:      .pervasive,
        heroNumberSize:          44,
        sectionTitleTracking:    0.8,
        sectionTitleUppercased: false
    )

    // Le Danger / Haute Tension. Signal d'alarme industriel — intensité maximale justifiée.
    // Pas de réduction des fills/glows — le jaune qui envahit EST la feature.
    static let electric = AppThemeColors(
        accent:          Color(hex: "FFFF33"),
        accentLight:     Color(hex: "FFFF80"),
        accentMuted:     Color(hex: "1F1F00"),
        onAccent:        .black,
        background:      Color(hex: "0F1000"),
        surfaceCard:     Color(hex: "262800"),
        surfaceElevated: Color(hex: "222400"),
        surfaceInset:    Color(hex: "0A0B00"),
        textPrimary:     Color(hex: "F5FFB0"),
        onBackground:    Color(hex: "F5FFB0"),
        onSurface:       Color(hex: "080900"),
        textSecondary:   Color(hex: "B8C800"),
        textMuted:       Color(hex: "4A5000"),
        separator:       Color(hex: "FFFF33").opacity(0.15),
        separatorSubtle: Color(hex: "FFFF33").opacity(0.08),
        separatorStrong: Color(hex: "FFFF33").opacity(0.30),
        danger:          Color(hex: "FF3B30"),
        success:         Color(hex: "00E5FF"),
        warning:         Color(hex: "FF9F0A"),
        info:            Color(hex: "38BDF8"),
        cardCornerRadius: 10,
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
        identityLayer:         .cyberGrid(opacity: 0.12),
        heroFontDesign:        .monospaced,
        titleFontDesign:       .default,
        displayWeight:         .semibold,
        cardAccentFillOpacity:   0.80,
        cardAccentStrokeOpacity: 0.25,
        cardStyle:               .floating,
        accentDistribution:      .pervasive,
        heroNumberSize:          40,
        sectionTitleTracking:    2.0,
        sectionTitleUppercased: true
    )

    // La Console / Code Froid. textPrimary == accent : lire les données = lire l'interface.
    // Pas d'ombres colorées sur un terminal CRT. Panneaux qui recèdent, données au premier plan.
    static let matrix = AppThemeColors(
        accent:          Color(hex: "00FF66"),
        accentLight:     Color(hex: "66FFB2"),
        accentMuted:     Color(hex: "003311"),
        onAccent:        Color(hex: "002000"),
        background:      Color(hex: "002000"),
        surfaceCard:     Color(hex: "103C10"),
        surfaceElevated: Color(hex: "143814"),
        surfaceInset:    Color(hex: "001800"),
        textPrimary:     Color(hex: "00FF66"),
        onBackground:    Color(hex: "00FF66"),
        onSurface:       Color(hex: "00FF66"),
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
        cardShadowColor:  .clear,                        // terminaux ne projettent pas d'ombres colorées
        cardShadowRadius: 0,
        cardShadowOffset: CGSize(width: 0, height: 2),
        cardGlowColor:    Color(hex: "00FF66").opacity(0.12),
        cardGlowRadius:   16,
        chartPalette:          [Color(hex: "00FF66"), Color(hex: "00CFFF"), Color(hex: "FFFF00"),
                                Color(hex: "FF6B2B"), Color(hex: "CC00FF")],
        glassOpacity:          0.15,
        accentGradientColors:  [Color(hex: "00FF66"), Color(hex: "007733")],
        identityLayer:         .scanlines(opacity: 0.09), // grain CRT présent — le vieux moniteur a une texture
        heroFontDesign:        .monospaced,
        titleFontDesign:       .monospaced,
        displayWeight:         .medium,
        cardAccentFillOpacity:   0.08,                   // panneaux qui recèdent, données au premier plan
        cardAccentStrokeOpacity: 0.25,
        cardStyle:               .outlined,
        accentDistribution:      .pervasive,
        heroNumberSize:        38,
        sectionTitleTracking:  2.5,
        sectionTitleUppercased: true
    )

    // Le Néon / Pluie sur Neon. Rose = signal néon. Violet = nuit mouillée qui l'absorbe.
    // Fond et surfaces inchangés — le violet reste le ciel, le rose prend tout le reste.
    static let tokyo = AppThemeColors(
        accent:          Color(hex: "FF6B9E"),
        accentLight:     Color(hex: "FFB3D1"),
        accentMuted:     Color(hex: "4A1030"),
        onAccent:        .white,
        background:      Color(hex: "1A0A48"),
        surfaceCard:     Color(hex: "2A1B7A"),
        surfaceElevated: Color(hex: "2A1972"),
        surfaceInset:    Color(hex: "12063A"),
        textPrimary:     Color(hex: "F0E8FF"),
        onBackground:    Color(hex: "F0E8FF"),
        onSurface:       Color(hex: "F0E8FF"),
        textSecondary:   Color(hex: "9B8FC0"),
        textMuted:       Color(hex: "554870"),
        separator:       Color(hex: "FF6B9E").opacity(0.08),
        separatorSubtle: Color(hex: "FF6B9E").opacity(0.04),
        separatorStrong: Color(hex: "FF6B9E").opacity(0.16),
        danger:          Color(hex: "FF453A"),
        success:         Color(hex: "34C759"),
        warning:         Color(hex: "FFD60A"),
        info:            Color(hex: "00D4FF"),
        cardCornerRadius: 28,
        cardBorderWidth:  1.0,
        cardBorderColor:  Color(hex: "FF6B9E").opacity(0.22),
        cardShadowColor:  Color(hex: "FF6B9E").opacity(0.18),
        cardShadowRadius: 12,
        cardShadowOffset: CGSize(width: 0, height: 4),
        cardGlowColor:    Color(hex: "FF6B9E").opacity(0.25),
        cardGlowRadius:   25,
        chartPalette:          [Color(hex: "FF6B9E"), Color(hex: "8B5CF6"), Color(hex: "00D4FF"),
                                Color(hex: "F59E0B"), Color(hex: "34C759")],
        glassOpacity:          0.18,
        accentGradientColors:  [Color(hex: "FF6B9E"), Color(hex: "8B5CF6")],
        identityLayer:         .neonHalo(color: Color(hex: "FF6B9E"), intensity: 0.30),
        heroFontDesign:        .rounded,
        titleFontDesign:       .rounded,
        displayWeight:         .bold,
        cardAccentFillOpacity:   0.15,
        cardAccentStrokeOpacity: 0.25,
        cardStyle:               .floating,
        accentDistribution:      .pervasive,
        heroNumberSize:          44,
        sectionTitleTracking:    0.3,
        sectionTitleUppercased: false
    )

    // La Glace / Le Seul Thème Clair. Fond glace + cards blanches. Texte foncé partout — inversion complète.
    // Accent = ombre dans la glace (#1A5F8A). cardStyle: .raised — ombre froide délimite les cards. Zéro glow.
    static let arctic = AppThemeColors(
        accent:          Color(hex: "1A5F8A"),
        accentLight:     Color(hex: "4A8FB5"),
        accentMuted:     Color(hex: "C5E0F0"),      // tint léger chips/badges
        onAccent:        Color(hex: "FFFFFF"),       // blanc sur bleu foncé — 6.9:1
        background:      Color(hex: "EAF4FF"),       // glace bleue
        surfaceCard:     Color(hex: "FFFFFF"),       // cards blanches
        surfaceElevated: Color(hex: "F5FAFF"),
        surfaceInset:    Color(hex: "D8ECFA"),
        textPrimary:     Color(hex: "0D1F2D"),       // 15.1:1 sur fond glace
        onBackground:    Color(hex: "0D1F2D"),       // = textPrimary, pas de divergence
        onSurface:       Color(hex: "0D1F2D"),
        textSecondary:   Color(hex: "4A6A7A"),       // 5.2:1 ✓ AA
        textMuted:       Color(hex: "6A8A9A"),       // 3.3:1 — muted intentionnel
        separator:       Color(hex: "1A5F8A").opacity(0.15),
        separatorSubtle: Color(hex: "1A5F8A").opacity(0.08),
        separatorStrong: Color(hex: "1A5F8A").opacity(0.28),
        danger:          Color(hex: "C0392B"),       // rouge foncé lisible sur clair
        success:         Color(hex: "1A7A40"),       // vert foncé lisible sur clair
        warning:         Color(hex: "9A5C00"),       // ambre foncé lisible sur clair
        info:            Color(hex: "1A5F8A"),
        cardCornerRadius: 20,
        cardBorderWidth:  1.0,
        cardBorderColor:  Color(hex: "1A5F8A").opacity(0.10),
        cardShadowColor:  Color(hex: "0D1F2D").opacity(0.10), // ombre froide — délimiteur principal
        cardShadowRadius: 10,
        cardShadowOffset: CGSize(width: 0, height: 3),
        cardGlowColor:    .clear,
        cardGlowRadius:   0,
        chartPalette:          [Color(hex: "1A5F8A"), Color(hex: "E85D04"), Color(hex: "1A7A40"),
                                Color(hex: "8B5CF6"), Color(hex: "E53E3E")],
        glassOpacity:          0.12,
        accentGradientColors:  [Color(hex: "1A5F8A"), Color(hex: "4A8FB5")],
        identityLayer:         .arcticFrost(opacity: 0.06),
        heroFontDesign:        .rounded,
        titleFontDesign:       .rounded,
        displayWeight:         .semibold,
        cardAccentFillOpacity:   0.0,
        cardAccentStrokeOpacity: 0.10,
        cardStyle:               .raised,
        accentDistribution:      .surgical,
        heroNumberSize:          40,
        sectionTitleTracking:    1.2,
        sectionTitleUppercased: false
    )

    // Coffre suisse à minuit. L'or n'apparaît qu'une fois par écran — foreground uniquement.
    // accentDistribution: .surgical — zéro fill/stroke doré sur les surfaces structurelles.
    // La bordure crème @0.06 est un fantôme de bord ; la séparation principale vient du delta surface/fond.
    static let goldNoir = AppThemeColors(
        accent:          Color(hex: "D4AF37"),
        accentLight:     Color(hex: "FFF7D6"),
        accentMuted:     Color(hex: "2A1C05"),
        onAccent:        Color(hex: "201408"),
        background:      Color(hex: "201408"),
        surfaceCard:     Color(hex: "3A2A18"),
        surfaceElevated: Color(hex: "322412"),
        surfaceInset:    Color(hex: "160C05"),
        textPrimary:     Color(hex: "FFF7D6"),
        onBackground:    Color(hex: "FFF7D6"),
        onSurface:       Color(hex: "FFF7D6"),
        textSecondary:   Color(hex: "B8A488"),           // crème chaude, moins saturé que l'or
        textMuted:       Color(hex: "7A6840"),
        separator:       Color(hex: "D4AF37").opacity(0.08),
        separatorSubtle: Color(hex: "D4AF37").opacity(0.04),
        separatorStrong: Color(hex: "D4AF37").opacity(0.14),
        danger:          Color(hex: "FF453A"),
        success:         Color(hex: "32D74B"),
        warning:         Color(hex: "FF9F0A"),
        info:            Color(hex: "64D2FF"),
        cardCornerRadius: 12,
        cardBorderWidth:  1.0,                           // fine = raffinement
        cardBorderColor:  Color(hex: "FFF7D6").opacity(0.06), // fantôme de bord, paroi du coffre
        cardShadowColor:  Color(hex: "110800").opacity(0.65), // ombre sombre = profondeur, pas dorée
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
        cardAccentFillOpacity:   0.0,                    // surgical — zéro fill doré
        cardAccentStrokeOpacity: 0.0,                    // surgical — zéro stroke overlay
        cardStyle:               .raised,
        accentDistribution:      .surgical,              // levier principal
        heroNumberSize:        36,
        sectionTitleTracking:  2.2,                      // espacement gravure formelle
        sectionTitleUppercased: true
    )

    // Jaune vif dominant — fond #FFFF33, cards sombres (Electric Dark inversé).
    // accent = noir sur fond jaune ; onAccent = jaune (pour les cards noires).
    // onBackground ≠ onSurface : seul thème du catalogue où ils divergent.
    static let electricLight = AppThemeColors(
        accent:          Color(hex: "0A0A00"),          // noir = "accent" sur fond jaune
        accentLight:     Color(hex: "1F1F00"),
        accentMuted:     Color(hex: "FFFF80"),          // jaune pâle = muted du jaune
        onAccent:        Color(hex: "FFFF33"),          // jaune sur fond noir (boutons)
        background:      Color(hex: "FFFF33"),          // ALL IN — fond jaune pur
        surfaceCard:     Color(hex: "1F1D00"),          // cards olive sombre, teinte jaune
        surfaceElevated: Color(hex: "1A1C00"),
        surfaceInset:    Color(hex: "060700"),
        textPrimary:     Color(hex: "F5FFB0"),          // = onSurface — texte sur cards
        onBackground:    Color(hex: "0A0A00"),          // noir sur fond jaune
        onSurface:       Color(hex: "F5FFB0"),          // clair sur cards sombres
        textSecondary:   Color(hex: "B8C800"),
        textMuted:       Color(hex: "4A5000"),
        separator:       Color(hex: "0A0A00").opacity(0.12),
        separatorSubtle: Color(hex: "0A0A00").opacity(0.06),
        separatorStrong: Color(hex: "0A0A00").opacity(0.25),
        danger:          Color(hex: "C41A0A"),          // rouge assombri (lisible sur jaune)
        success:         Color(hex: "007A33"),          // vert foncé (lisible sur jaune)
        warning:         Color(hex: "8B5E00"),          // ambre foncé
        info:            Color(hex: "005FA3"),          // bleu foncé
        cardCornerRadius: 18,
        cardBorderWidth:  1.5,
        cardBorderColor:  Color(hex: "FFFF33").opacity(0.45),
        cardShadowColor:  Color(hex: "FFFF33").opacity(0.35),
        cardShadowRadius: 12,
        cardShadowOffset: CGSize(width: 0, height: 4),
        cardGlowColor:    Color(hex: "FFFF33").opacity(0.55),
        cardGlowRadius:   35,
        chartPalette:          [Color(hex: "0A0A00"), Color(hex: "005FA3"), Color(hex: "C41A0A"),
                                Color(hex: "007A33"), Color(hex: "6B21A8")],
        glassOpacity:          0.35,
        accentGradientColors:  [Color(hex: "0A0A00"), Color(hex: "1F1F00")],
        identityLayer:         .cyberGrid(opacity: 0.08),  // grille noire sur fond jaune
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

    // Camp d'entraînement, 16h, chaleur crue. Terracotta = la terre, pas le luxe.
    // accentDistribution: .pervasive — le sable doré est une variation de la terre, pas un accent décoratif.
    // Pas de glow — lumière crue de plein jour, pas de néon.
    static let desert = AppThemeColors(
        accent:          Color(hex: "E9C46A"),
        accentLight:     Color(hex: "F4D08A"),
        accentMuted:     Color(hex: "4A2C08"),
        onAccent:        Color(hex: "2C1810"),
        background:      Color(hex: "5C3D2E"),
        surfaceCard:     Color(hex: "7A5A48"),
        surfaceElevated: Color(hex: "7A5542"),
        surfaceInset:    Color(hex: "4A3020"),
        textPrimary:     Color(hex: "FFF0DC"),
        onBackground:    Color(hex: "FFF0DC"),
        onSurface:       Color(hex: "FFF0DC"),
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
        cardGlowColor:    .clear,                        // pas de glow — lumière crue
        cardGlowRadius:   0,
        chartPalette:          [Color(hex: "E9C46A"), Color(hex: "D4A373"), Color(hex: "F4A261"),
                                Color(hex: "264653"), Color(hex: "2A9D8F")],
        glassOpacity:          0.12,
        accentGradientColors:  [Color(hex: "E9C46A"), Color(hex: "D4A373")],
        identityLayer:         .filmGrain(opacity: 0.06), // grain de terre craquelée
        heroFontDesign:        .default,                  // rustique, pas engravement serif
        titleFontDesign:       .default,
        displayWeight:         .bold,                     // les chiffres frappent
        cardAccentFillOpacity:   0.14,
        cardAccentStrokeOpacity: 0.10,                   // contour réduit — matière, pas dorure
        cardStyle:               .raised,
        accentDistribution:      .pervasive,
        heroNumberSize:        40,
        sectionTitleTracking:  1.2,                      // tension, pas décontraction
        sectionTitleUppercased: true
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
        case .goldNoir:      return .goldNoir
        case .desert:        return .desert
        case .electricLight: return .electricLight
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
    var onBackground:    Color { colors.onBackground }
    var onSurface:       Color { colors.onSurface }
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
