import Foundation
import SwiftUI

struct PhoenixScore: Codable {
    let score: Double
    let state: String
    let axes: PhoenixAxes
    let isFoundation: Bool
    let rawDelta: Double
    let guidance: PhoenixGuidance?

    private static let foundationAxes = PhoenixAxes(
        workout:   PhoenixAxisData(delta: 0),
        stress:    PhoenixAxisData(delta: 0),
        nutrition: PhoenixAxisData(delta: 0),
        spirit:    nil
    )

    enum CodingKeys: String, CodingKey {
        case score, state, axes, guidance
        case isFoundation = "is_foundation"
        case rawDelta     = "raw_delta"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        score        = (try? c.decodeIfPresent(Double.self,          forKey: .score))        ?? 0.0
        state        = (try? c.decodeIfPresent(String.self,          forKey: .state))        ?? "foundation"
        axes         = (try? c.decodeIfPresent(PhoenixAxes.self,     forKey: .axes))         ?? PhoenixScore.foundationAxes
        isFoundation = (try? c.decodeIfPresent(Bool.self,            forKey: .isFoundation)) ?? true
        rawDelta     = (try? c.decodeIfPresent(Double.self,          forKey: .rawDelta))     ?? 0.0
        guidance     = try? c.decodeIfPresent(PhoenixGuidance.self,  forKey: .guidance)
    }

    var phoenixState: PhoenixState {
        PhoenixState(rawValue: state) ?? .foundation
    }
}

struct PhoenixAxes: Codable {
    let workout: PhoenixAxisData
    let stress: PhoenixAxisData
    let nutrition: PhoenixAxisData
    let spirit: PhoenixAxisData?
}

struct PhoenixAxisData: Codable {
    let delta: Double
    let hasBaseline: Bool

    private struct Details: Codable {
        let hasBaseline: Bool?
        enum CodingKeys: String, CodingKey { case hasBaseline = "has_baseline" }
    }

    init(delta: Double, hasBaseline: Bool = true) {
        self.delta = delta
        self.hasBaseline = hasBaseline
    }

    init(from decoder: Decoder) throws {
        let c       = try decoder.container(keyedBy: CodingKeys.self)
        delta       = (try? c.decodeIfPresent(Double.self, forKey: .delta))   ?? 0.0
        let details = try? c.decodeIfPresent(Details.self, forKey: .details)
        hasBaseline = details?.hasBaseline ?? true
    }

    enum CodingKeys: String, CodingKey { case delta, details }
}

struct PhoenixGuidance: Codable {
    let workout:   String?
    let stress:    String?
    let nutrition: String?
    let spirit:    String?
}

enum PhoenixState: String, Codable {
    case foundation      = "foundation"
    case cendres         = "cendres"
    case braises         = "braises"
    case braisesChaud    = "braises_chaudes"
    case flamme          = "flamme"
    case envol           = "envol"
    case supernova       = "supernova"

    var label: String {
        switch self {
        case .foundation:   return "Fondation"
        case .cendres:      return "Cendres"
        case .braises:      return "Braises"
        case .braisesChaud: return "Braises chaudes"
        case .flamme:       return "Flamme"
        case .envol:        return "Envol"
        case .supernova:    return "Supernova"
        }
    }

    var scoreColor: Color {
        switch self {
        case .foundation:   return Color(hex: "6B8CFF")
        case .cendres:      return Color(white: 0.45)
        case .braises:      return Color(hex: "C05020")
        case .braisesChaud: return Color(hex: "E07030")
        case .flamme:       return Color(hex: "F5A623")
        case .envol:        return Color(hex: "FFD700")
        case .supernova:    return .white
        }
    }

    var glowColor: Color {
        switch self {
        case .foundation:   return Color(hex: "6B8CFF")
        case .cendres:      return Color(white: 0.3)
        case .braises:      return Color(hex: "C05020")
        case .braisesChaud: return Color(hex: "E07030")
        case .flamme:       return Color(hex: "F5A623")
        case .envol:        return Color(hex: "FFD700")
        case .supernova:    return .white
        }
    }

    var glowRadius: CGFloat {
        switch self {
        case .foundation:   return 8
        case .cendres:      return 0
        case .braises:      return 4
        case .braisesChaud: return 8
        case .flamme:       return 14
        case .envol:        return 22
        case .supernova:    return 32
        }
    }

    var glowOpacity: Double {
        switch self {
        case .foundation:   return 0.20
        case .cendres:      return 0.0
        case .braises:      return 0.10
        case .braisesChaud: return 0.18
        case .flamme:       return 0.30
        case .envol:        return 0.40
        case .supernova:    return 0.55
        }
    }

    var cardBackground: Color {
        switch self {
        case .foundation:   return Color(hex: "0D1020")
        case .cendres:      return Color(hex: "111111")
        case .braises:      return Color(hex: "120A05")
        case .braisesChaud: return Color(hex: "160D05")
        case .flamme:       return Color(hex: "1A0E00")
        case .envol:        return Color(hex: "1A1200")
        case .supernova:    return Color(hex: "221A08")   // warm ivory-dark — seul fond chaud de l'app
        }
    }

    var particleCount: Int {
        switch self {
        case .foundation:   return 15
        case .cendres:      return 12
        case .braises:      return 18
        case .braisesChaud: return 22
        case .flamme:       return 28
        case .envol:        return 34
        case .supernova:    return 40
        }
    }
}
