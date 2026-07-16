import Foundation
import SwiftUI

// MARK: - Energy Daily

struct EnergyDaily: Codable {
    // Erreur profil incomplet
    let error: String?
    let message: String?
    let missing: [String]?

    // Données calculées
    let date: String?
    let bmr: Int?
    let bmrElapsed: Int?
    let tdeeProgress: Double?
    let bmrFormula: String?
    let eatWorkouts: Int?
    let eatCardio: Int?
    let neat: Int?
    let tdee: Int?
    let intake: Int?
    let balance: Int?
    let balanceStatus: String?
    let isTooEarly: Bool?
    let objective: String?
    let targetBalance: String?
    let breakdown: EnergyBreakdown?

    var isError: Bool { error != nil }

    enum CodingKeys: String, CodingKey {
        case error, message, missing, date, bmr, neat, tdee, intake, balance, objective, breakdown
        case bmrElapsed    = "bmr_elapsed"
        case tdeeProgress  = "tdee_progress"
        case bmrFormula    = "bmr_formula"
        case eatWorkouts   = "eat_workouts"
        case eatCardio     = "eat_cardio"
        case balanceStatus = "balance_status"
        case isTooEarly    = "is_too_early"
        case targetBalance = "target_balance"
    }
}

// MARK: - Breakdown

struct EnergyBreakdown: Codable {
    let workouts: [EnergySession]?
    let cardio: [EnergySession]?
    let steps: Int?
    let stepsNet: Int?
    let neatCalories: Int?

    enum CodingKeys: String, CodingKey {
        case workouts, cardio, steps
        case stepsNet     = "steps_net"
        case neatCalories = "neat_calories"
    }
}

struct EnergySession: Codable, Identifiable {
    let type: String
    let name: String?
    let durationMin: Int?
    let calories: Int
    let rpe: Int?
    let met: Double?
    let source: String?

    var id: String { "\(type)-\(durationMin ?? 0)-\(calories)-\(name ?? "")" }

    enum CodingKeys: String, CodingKey {
        case type, name, calories, rpe, met, source
        case durationMin = "duration_min"
    }
}

// MARK: - History (7j)

struct EnergyHistoryDay: Codable, Identifiable {
    var id: String { date }
    let date: String
    let bmr: Int
    let eatWorkouts: Int
    let eatCardio: Int
    let neat: Int?
    let tdee: Int
    let intake: Int?
    let balance: Int?
    let balanceStatus: String?
    let hasData: Bool

    enum CodingKeys: String, CodingKey {
        case date, bmr, tdee, intake, balance, neat
        case eatWorkouts   = "eat_workouts"
        case eatCardio     = "eat_cardio"
        case balanceStatus = "balance_status"
        case hasData       = "has_data"
    }

    var isSurplus: Bool { (balance ?? 0) >= 0 }

    var shortDate: String {
        let parts = date.split(separator: "-")
        guard parts.count == 3 else { return date }
        return "\(parts[2])/\(parts[1])"
    }
}

// MARK: - Display helpers

extension EnergyDaily {
    // Source unique assumée — le backend expose balance_status, ce mapping 0-100
    // est la présentation iOS. Décision d'audit juillet 2026 : pas de score
    // backend, un seul consommateur. Toute évolution du mapping se fait ici et
    // nulle part ailleurs.
    var energyScore: Int {
        switch balanceStatus {
        case "balanced":         return 90
        case "surplus_optimal":  return 85
        case "deficit_optimal":  return 85
        case "surplus_low":      return 65
        case "deficit_light":    return 65
        case "surplus_high":     return 50
        case "surplus":          return 50
        case "deficit":          return 45
        case "deficit_aggressive": return 35
        case "deficit_severe":   return 15
        default:                 return 50
        }
    }

    var statusLabel: String {
        switch balanceStatus {
        case "balanced":           return "Équilibré"
        case "surplus_optimal":    return "Surplus optimal"
        case "deficit_optimal":    return "Déficit optimal"
        case "surplus_low":        return "Surplus léger"
        case "surplus_high":       return "Surplus élevé"
        case "surplus":            return "En surplus"
        case "deficit_light":      return "Déficit léger"
        case "deficit":            return "En déficit"
        case "deficit_aggressive": return "Déficit agressif"
        case "deficit_severe":     return "Déficit sévère"
        default:                   return "—"
        }
    }

    var statusColor: Color {
        let score = energyScore
        if score >= 75 { return .statusGreen }
        if score >= 50 { return .statusOrange }
        return .statusRed
    }

    var bmrFormulaLabel: String {
        bmrFormula == "katch_mcArdle" ? "Katch-McArdle" : "Mifflin-St Jeor"
    }

    var bmrFormulaProgressLabel: String {
        guard let progress = tdeeProgress, progress < 0.99 else {
            return bmrFormulaLabel
        }
        return "\(bmrFormulaLabel) · \(Int(progress * 100))% du jour"
    }

    var formattedBalance: String {
        guard let b = balance else { return "—" }
        return b >= 0 ? "+\(b) kcal" : "\(b) kcal"
    }
}
