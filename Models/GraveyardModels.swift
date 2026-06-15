import Foundation
import SwiftUI

struct GraveyardCount: Codable {
    let totalCount: Int
    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
    }
}

struct GraveyardResponse: Codable {
    let tombstones: [Tombstone]
    let totalCount: Int
    let inceptionDate: String?

    enum CodingKeys: String, CodingKey {
        case tombstones
        case totalCount   = "total_count"
        case inceptionDate = "inception_date"
    }
}

struct Tombstone: Codable, Identifiable {
    let id: String
    let type: String
    let title: String
    let epitaph: String
    let deathDate: String
    let bornDate: String?
    let oldValue: Double?
    let newValue: Double?
    let exerciseName: String?
    let daysSinceDeath: Int

    enum CodingKeys: String, CodingKey {
        case id, type, title, epitaph
        case deathDate     = "death_date"
        case bornDate      = "born_date"
        case oldValue      = "old_value"
        case newValue      = "new_value"
        case exerciseName  = "exercise_name"
        case daysSinceDeath = "days_since_death"
    }

    var tombstoneType: TombstoneType {
        TombstoneType(rawValue: type) ?? .prKilled
    }
}

enum TombstoneType: String {
    case prKilled      = "pr_killed"
    case plateauBuried = "plateau_buried"
    case streakSlain   = "streak_slain"
    case stressFloor   = "stress_floor"
    case bodycompShed  = "bodycomp_shed"

    var icon: String {
        switch self {
        case .prKilled:      return "dumbbell.fill"
        case .plateauBuried: return "mountain.2.fill"
        case .streakSlain:   return "flame.fill"
        case .stressFloor:   return "brain.head.profile"
        case .bodycompShed:  return "scalemass.fill"
        }
    }

    var label: String {
        switch self {
        case .prKilled:      return "PR DÉTRUIT"
        case .plateauBuried: return "PLATEAU ENTERRÉ"
        case .streakSlain:   return "STREAK TUÉ"
        case .stressFloor:   return "NOUVEAU PLANCHER"
        case .bodycompShed:  return "POIDS ENTERRÉ"
        }
    }

    var accentColor: Color {
        switch self {
        case .prKilled:      return .statusOrange
        case .plateauBuried: return Color(hex: "8B6AFF")
        case .streakSlain:   return Color(hex: "FF6B35")
        case .stressFloor:   return Color(hex: "4ECDC4")
        case .bodycompShed:  return Color(hex: "A8E6CF")
        }
    }
}
