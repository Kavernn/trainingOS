import Foundation
import SwiftUI

struct PhoenixScore: Codable {
    let score: Double
    let state: String
    let axes: PhoenixAxes
    let isFoundation: Bool
    let rawDelta: Double

    enum CodingKeys: String, CodingKey {
        case score, state, axes
        case isFoundation = "is_foundation"
        case rawDelta     = "raw_delta"
    }

    var phoenixState: PhoenixState {
        PhoenixState(rawValue: state) ?? .foundation
    }
}

struct PhoenixAxes: Codable {
    let workout: PhoenixAxisData
    let stress: PhoenixAxisData
    let nutrition: PhoenixAxisData
}

struct PhoenixAxisData: Codable {
    let delta: Double
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
        case .supernova:    return Color(hex: "1C1400")
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
