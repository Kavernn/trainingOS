import SwiftUI
import AVFoundation

// MARK: - Button Styles

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - API Config (single source of truth for base URL and auth)
enum APIConfig {
    static let base = "https://training-os-rho.vercel.app"
    // apiKey est défini dans Utilities/APIConfig.swift (gitignored — ne jamais commiter)
}

// MARK: - Design tokens (spacing / radius)
//
// Système visuel unique — remplace les magic numbers de spacing et radius
// éparpillés dans les vues. Deux échelles radius : appCardRadius pour les
// cartes et poids "conteneur", appPillRadius pour badges et chips.
extension CGFloat {
    static let appPagePadding:    CGFloat = 16   // padding horizontal des pages
    static let appSectionSpacing: CGFloat = 24   // entre grandes sections
    static let appCardSpacing:    CGFloat = 12   // entre cartes d'une même section
    static let appCardRadius:     CGFloat = 14   // cartes racine
    static let appCardInsetH:     CGFloat = 16   // padding H interne carte
    static let appCardInsetV:     CGFloat = 14   // padding V interne carte
    static let appHairline:       CGFloat = 0.5  // dividers subtils
    static let appPillRadius:     CGFloat = 6    // badges et petits chips
}

// MARK: - Safe Calendar Operations
extension Calendar {
    func safeDateByAdding(_ component: Calendar.Component, value: Int, to date: Date) -> Date {
        return self.date(byAdding: component, value: value, to: date) ?? date
    }
    func safeDate(bySettingHour hour: Int, minute: Int, second: Int, of date: Date) -> Date {
        return self.date(bySettingHour: hour, minute: minute, second: second, of: date) ?? date
    }
}

// MARK: - Keyboard dismiss

extension View {
    func hideKeyboard() {
#if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
#endif
    }

    /// Dismisses the keyboard when the user taps on any non-interactive background area.
    /// Buttons and text fields in the foreground still consume their own taps normally.
    func dismissKeyboardOnTap() -> some View {
        background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { hideKeyboard() }
        )
    }
}

extension Color {
    static var appBg:              Color { AppTheme.shared.background }
    static var appCard:            Color { AppTheme.shared.surfaceCard }
    static var appBgSecondary:     Color { AppTheme.shared.surfaceElevated }
    static var appSurfaceInset:    Color { AppTheme.shared.surfaceInset }
    static var forge:     Color { AppTheme.shared.accent }
    static var forgeDeep: Color { AppTheme.shared.accentLight }
    static var appAccentUltraLight:Color { AppTheme.shared.accentMuted }
    static var appDanger:          Color { AppTheme.shared.danger }
    static var appSuccess:         Color { AppTheme.shared.success }
    static var appWarning:         Color { AppTheme.shared.warning }
    static var appInfo:            Color { AppTheme.shared.info }
    static var appTextPrimary:     Color { AppTheme.shared.textPrimary }
    static var appOnBackground:    Color { AppTheme.shared.onBackground }
    static var appOnSurface:       Color { AppTheme.shared.onSurface }
    static var appTextSecondary:   Color { AppTheme.shared.textSecondary }
    static var appTextTertiary:    Color { AppTheme.shared.textMuted }
    static var appTextMuted:       Color { AppTheme.shared.textMuted }
    static var onAccent:           Color { AppTheme.shared.onAccent }
    static var appSeparator:       Color { AppTheme.shared.separator }
    static var appSeparatorSubtle: Color { AppTheme.shared.separatorSubtle }
    static var appSeparatorStrong: Color { AppTheme.shared.separatorStrong }
    static var trendPositive: Color { isSurgical ? Color(white: 0.68) : isElectricLight ? Color(hex: "FFFF33") : Color(hex: "34C759") }
    static var trendNeutral:  Color { isSurgical ? Color(white: 0.50) : Color(hex: "FF9500") }
    static var trendNegative: Color { isSurgical ? Color(white: 0.35) : Color(hex: "FF6B6B") }
    static var accentOnSurface: Color { isElectricLight ? Color(hex: "FFFF33") : AppTheme.shared.accent }
    static var moonlight:     Color { isSurgical ? Color(white: 0.80) : Color(hex: "E8EDF5") }
    static let voidBg          = Color(red: 0.020, green: 0.031, blue: 0.063)  // Fond de mood fixe — NE suit pas le thème, intentionnel
static let pssBg           = Color(hex: "0C0C18")  // Fond de mood fixe — NE suit pas le thème, intentionnel (cf .voidBg)
    static let ritualEveningBg = Color(hex: "0D0906")  // Fond de mood fixe — NE suit pas le thème, intentionnel (cf .voidBg)

    // Couleurs sémantiques — desaturées en mode surgical (Sin City N&B)
    static var statusGreen:  Color { isSurgical ? Color(white: 0.68) : .green   }
    static var statusOrange: Color { isSurgical ? Color(white: 0.55) : .orange  }
    static var statusBlue:   Color { isSurgical ? Color(white: 0.50) : isElectricLight ? Color(hex: "FFFF33") : .blue    }
    static var statusPurple: Color { isSurgical ? Color(white: 0.58) : .purple  }
    static var statusYellow: Color { isSurgical ? Color(white: 0.62) : .yellow  }
    static var statusCyan:   Color { isSurgical ? Color(white: 0.52) : isElectricLight ? Color(hex: "FFFF33") : .cyan    }
    static var statusRed:    Color { isSurgical ? Color(white: 0.72) : .red     }

    private static var isSurgical: Bool {
        AppTheme.shared.colors.accentDistribution == .surgical
    }

    private static var isElectricLight: Bool {
        AppTheme.shared.selectedTheme == .electricLight
    }

    // Couleur canonique d'un type de séance — unique source de vérité, surgical-aware
    static func sessionTypeColor(_ type: String) -> Color {
        let low = type.lowercased()
        if low.contains("repos") || low.contains("recovery") || low.contains("rest") { return .statusGreen }
        if low.contains("pull")   { return .statusCyan }
        if low.contains("push") || low.contains("upper") { return .statusOrange }
        if low.contains("legs") || low.contains("lower") { return .statusYellow }
        if low.contains("yoga")   { return .statusPurple }
        if low.contains("full body") { return .statusCyan }
        return .statusBlue
    }

    // Composition corporelle — deux séries stables, indépendantes du thème (lisibilité graphe)
    enum BodyCompSeries { case lean, fat }
    static func bodyComp(_ series: BodyCompSeries) -> Color {
        switch series {
        case .lean: return Color(hex: "F5A623")  // ambre — masse maigre
        case .fat:  return Color(hex: "E74C3C")  // rouge sémantique universel — masse grasse
        }
    }

    // Mood viz palette — violet→teal→green, non-moralistic gradient (intentional fixed)
    static func moodColor(for score: Int) -> Color {
        if score >= 8 { return Color.trendPositive }
        if score >= 5 { return .statusCyan }
        return Color(hex: "8B5CF6")  // indigo — introspective, not alarming
    }

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red:   Double(r) / 255,
                  green: Double(g) / 255,
                  blue:  Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

extension DateFormatter {
    static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/Montreal") ?? .current
        return f
    }()

    static let isoYearMonth: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/Montreal") ?? .current
        return f
    }()

    static let shortDateFR: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        f.locale = Locale(identifier: "fr_FR")
        return f
    }()

    static let longDateFR: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        f.locale = Locale(identifier: "fr_FR")
        return f
    }()

    static let monthYearFR: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        f.locale = Locale(identifier: "fr_FR")
        return f
    }()

    static let shortDateFRCA: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        f.locale = Locale(identifier: "fr_CA")
        return f
    }()
}

extension NumberFormatter {
    static let spaceGrouped: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        f.maximumFractionDigits = 0
        return f
    }()
}

// MARK: - Beep generator (WAV en mémoire, joue par-dessus la musique)
/// Génère un bip sinusoïdal à la fréquence `hz` et le retourne prêt à jouer.
/// Utilise AVAudioSession .playback + .mixWithOthers : audible même en mode silencieux,
/// sans couper la musique en cours de lecture.
func makeBeep(hz: Double, duration: Double) -> AVAudioPlayer? {
    let rate  = 44100
    let count = Int(Double(rate) * duration)
    var wav   = Data()

    func w16(_ v: Int16) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
    func w32(_ v: Int32) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }

    wav.append(contentsOf: "RIFF".utf8); w32(Int32(36 + count * 2))
    wav.append(contentsOf: "WAVE".utf8)
    wav.append(contentsOf: "fmt ".utf8); w32(16); w16(1); w16(1)
    w32(Int32(rate)); w32(Int32(rate * 2)); w16(2); w16(16)
    wav.append(contentsOf: "data".utf8); w32(Int32(count * 2))
    for i in 0..<count {
        let t   = Double(i) / Double(rate)
        let env = min(1.0, min(t / 0.005, (duration - t) / 0.005))
        w16(Int16(env * 28000 * sin(2 * .pi * hz * t)))
    }

#if os(iOS)
    try? AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
    try? AVAudioSession.sharedInstance().setActive(true)
#endif
    let player = try? AVAudioPlayer(data: wav, fileTypeHint: "wav")
    player?.prepareToPlay()
    return player
}

// MARK: - Montreal timezone calendar (shared helper — _today_mtl() equivalent for iOS)
extension Calendar {
    static let mtl: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "America/Montreal") ?? .current
        return c
    }()
}

// MARK: - ISO Week helpers
extension Date {
    // "YYYY-Www" — ISO 8601 week key, Monday-based
    var isoWeekKey: String {
        let cal = Calendar(identifier: .iso8601)
        let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        guard let yr = c.yearForWeekOfYear, let wk = c.weekOfYear else { return "" }
        return String(format: "%d-W%02d", yr, wk)
    }

    // Returns (monday, sunday) as "YYYY-MM-DD", weeksAgo weeks back
    func isoWeekBounds(weeksAgo: Int = 0) -> (String, String) {
        let cal = Calendar(identifier: .iso8601)
        let target = cal.safeDateByAdding(.weekOfYear, value: -weeksAgo, to: self)
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: target)
        comps.weekday = 2
        let monday = cal.date(from: comps) ?? self
        let sunday = cal.safeDateByAdding(.day, value: 6, to: monday)
        return (DateFormatter.isoDate.string(from: monday), DateFormatter.isoDate.string(from: sunday))
    }
}

// MARK: - Model UI extensions (color helpers that need SwiftUI but must not live in Models/)
extension PSSRecord {
    var categoryColor: Color {
        switch category {
        case "low":      return .statusGreen
        case "moderate": return .statusOrange
        default:         return .statusRed
        }
    }
}

// MARK: - Muscle group localization
extension String {
    var localizedMuscleGroup: String {
        switch self.lowercased() {
        case "glutes", "fessiers":                      return "Fessiers"
        case "chest", "pectorals", "pectoral":          return "Pectoraux"
        case "back":                                    return "Dos"
        case "lats", "lat":                             return "Dorsaux"
        case "shoulders", "deltoids":                   return "Épaules"
        case "rear delt", "rear delts",
             "posterior deltoid":                       return "Post. Épaule"
        case "biceps", "bicep":                         return "Biceps"
        case "triceps", "tricep":                       return "Triceps"
        case "legs", "quads", "quadriceps":             return "Quadriceps"
        case "hamstrings":                              return "Ischio-jambiers"
        case "calves":                                  return "Mollets"
        case "core", "abs":                             return "Core"
        case "obliques":                                return "Obliques"
        case "forearms":                                return "Avant-bras"
        case "traps", "trapezius":                      return "Trapèzes"
        case "rhomboids", "rhomboid":                   return "Rhomboïdes"
        case "lower back":                              return "Lombaires"
        case "rotators":                                return "Rotateurs"
        case "abductors":                               return "Abducteurs"
        default:                                        return self.capitalized
        }
    }
}
