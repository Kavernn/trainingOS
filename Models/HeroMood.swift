import Foundation

enum HeroMood: String, CaseIterable, Identifiable {
    case mountainDiscipline = "mountainDiscipline"
    case stormAttack = "stormAttack"
    case oceanCalm = "oceanCalm"
    case forestReset = "forestReset"
    case cityNightExecute = "cityNightExecute"
    case desertResilience = "desertResilience"
    case auroraElevated = "auroraElevated"
    case minimalDark = "minimalDark"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mountainDiscipline: return "Mountain / Discipline"
        case .stormAttack: return "Storm / Attack"
        case .oceanCalm: return "Ocean / Calm"
        case .forestReset: return "Forest / Reset"
        case .cityNightExecute: return "City Night / Execute"
        case .desertResilience: return "Desert / Resilience"
        case .auroraElevated: return "Aurora / Elevated"
        case .minimalDark: return "Minimal Dark"
        }
    }

    var assetName: String {
        switch self {
        case .mountainDiscipline: return "HeroMoodMountain"
        case .stormAttack: return "HeroMoodStorm"
        case .oceanCalm: return "HeroMoodOcean"
        case .forestReset: return "HeroMoodForest"
        case .cityNightExecute: return "HeroMoodCityNight"
        case .desertResilience: return "HeroMoodDesert"
        case .auroraElevated: return "HeroMoodAurora"
        case .minimalDark: return "HeroMoodMinimalDark"
        }
    }
}

enum HeroMoodPreference {
    static let storageKey = "dashboard_hero_mood"
    static let currentRawValue = ""
    static let currentDisplayName = "Hero actuel"

    static func normalizedRawValue(_ rawValue: String) -> String {
        guard !rawValue.isEmpty else { return currentRawValue }
        return HeroMood(rawValue: rawValue)?.rawValue ?? currentRawValue
    }
}
