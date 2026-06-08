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
    let accent:              Color
    let accentLight:         Color
    let accentUltraLight:    Color
    let accentText:          Color
    let background:          Color
    let backgroundCard:      Color
    let backgroundSecondary: Color
    let textPrimary:         Color
    let textSecondary:       Color
    let textTertiary:        Color
    let separator:           Color
    let danger:              Color
    let success:             Color
    let warning:             Color
}

extension AppThemeColors {
    static let monochrome = AppThemeColors(
        accent:              Color(hex: "1C1C1E"),
        accentLight:         Color(hex: "3A3A3C"),
        accentUltraLight:    Color(hex: "F2F2F7"),
        accentText:          .white,
        background:          .black,
        backgroundCard:      Color(hex: "1C1C1E"),
        backgroundSecondary: Color(hex: "2C2C2E"),
        textPrimary:         .white,
        textSecondary:       Color.white.opacity(0.6),
        textTertiary:        Color.white.opacity(0.3),
        separator:           Color(hex: "38383A"),
        danger:              Color(hex: "FF453A"),
        success:             Color(hex: "32D74B"),
        warning:             Color(hex: "FFD60A")
    )

    static let electric = AppThemeColors(
        accent:              Color(hex: "E8FF00"),
        accentLight:         Color(hex: "F4FF66"),
        accentUltraLight:    Color(hex: "1E2000"),
        accentText:          .black,
        background:          .black,
        backgroundCard:      Color(hex: "0A0A0A"),
        backgroundSecondary: Color(hex: "111111"),
        textPrimary:         .white,
        textSecondary:       Color(hex: "AAAAAA"),
        textTertiary:        Color(hex: "555555"),
        separator:           Color(hex: "222222"),
        danger:              Color(hex: "FF3B30"),
        success:             Color(hex: "E8FF00"),
        warning:             Color(hex: "FF9F0A")
    )

    static let blood = AppThemeColors(
        accent:              Color(hex: "C0392B"),
        accentLight:         Color(hex: "E74C3C"),
        accentUltraLight:    Color(hex: "2D0A08"),
        accentText:          .white,
        background:          Color(hex: "1A1A1A"),
        backgroundCard:      Color(hex: "242424"),
        backgroundSecondary: Color(hex: "2E2E2E"),
        textPrimary:         Color(hex: "F5F5F5"),
        textSecondary:       Color(hex: "AAAAAA"),
        textTertiary:        Color(hex: "666666"),
        separator:           Color(hex: "333333"),
        danger:              Color(hex: "FF453A"),
        success:             Color(hex: "2ECC71"),
        warning:             Color(hex: "F39C12")
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

    // Raccourcis directs
    var accent:              Color { colors.accent }
    var accentLight:         Color { colors.accentLight }
    var accentUltraLight:    Color { colors.accentUltraLight }
    var accentText:          Color { colors.accentText }
    var background:          Color { colors.background }
    var backgroundCard:      Color { colors.backgroundCard }
    var backgroundSecondary: Color { colors.backgroundSecondary }
    var textPrimary:         Color { colors.textPrimary }
    var textSecondary:       Color { colors.textSecondary }
    var textTertiary:        Color { colors.textTertiary }
    var separator:           Color { colors.separator }
    var danger:              Color { colors.danger }
    var success:             Color { colors.success }
    var warning:             Color { colors.warning }

    // Opacités glass selon thème
    var glassOpacity: Double {
        switch selectedTheme {
        case .monochrome: return 0.1
        case .electric:   return 0.2
        case .blood:      return 0.15
        }
    }
}
