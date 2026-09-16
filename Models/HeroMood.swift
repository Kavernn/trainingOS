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
    case atmosphereParis = "display_atmosphere_paris"
    case atmosphereRome = "display_atmosphere_rome"
    case artsMural = "display_arts_mural"
    case artsGallery = "display_arts_gallery"
    case culturePottery = "display_culture_pottery"
    case cultureDance = "display_culture_dance"
    case historyRuins = "display_history_ruins"
    case historyCastle = "display_history_castle"
    case sportsBroncosGame = "display_sports_broncos_game"
    case sportsBroncosTailgate = "display_sports_broncos_tailgate"

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
        case .atmosphereParis: return "Soirée parisienne"
        case .atmosphereRome: return "Rome au coucher du soleil"
        case .artsMural: return "Murales et couleurs"
        case .artsGallery: return "Galerie contemporaine"
        case .culturePottery: return "Savoir-faire artisanal"
        case .cultureDance: return "Danse traditionnelle"
        case .historyRuins: return "Ruines antiques"
        case .historyCastle: return "Château médiéval"
        case .sportsBroncosGame: return "Broncos — Jour de match"
        case .sportsBroncosTailgate: return "Broncos — Esprit de match"
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
        case .atmosphereParis: return "display_atmosphere_paris"
        case .atmosphereRome: return "display_atmosphere_rome"
        case .artsMural: return "display_arts_mural"
        case .artsGallery: return "display_arts_gallery"
        case .culturePottery: return "display_culture_pottery"
        case .cultureDance: return "display_culture_dance"
        case .historyRuins: return "display_history_ruins"
        case .historyCastle: return "display_history_castle"
        case .sportsBroncosGame: return "display_sports_broncos_game"
        case .sportsBroncosTailgate: return "display_sports_broncos_tailgate"
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
