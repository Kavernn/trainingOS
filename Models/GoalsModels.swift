import Foundation

// MARK: - Objectifs
struct ObjectifEntry: Identifiable {
    var id: String { exercise }
    let exercise: String
    let current: Double
    let goal: Double
    let achieved: Bool
    let deadline: String
    let note: String
    var archived: Bool = false
}

// MARK: - Smart Goals
struct SmartGoalEntry: Identifiable, Codable {
    let id: String
    let type: String
    let targetValue: Double
    let initialValue: Double?
    let currentValue: Double?
    let targetDate: String
    let label: String
    let unit: String
    let lowerIsBetter: Bool
    let progress: Double   // 0–100
    let achieved: Bool

    enum CodingKeys: String, CodingKey {
        case id, type, label, unit, progress, achieved
        case targetValue   = "target_value"
        case initialValue  = "initial_value"
        case currentValue  = "current_value"
        case targetDate    = "target_date"
        case lowerIsBetter = "lower_is_better"
    }
}

extension SmartGoalEntry {
    var icon: String {
        switch type {
        case "body_fat":           return "flame.fill"
        case "lean_mass":          return "figure.strengthtraining.traditional"
        case "waist_cm":           return "arrow.left.and.right"
        case "weekly_volume":      return "chart.bar.fill"
        case "training_frequency": return "calendar.badge.checkmark"
        case "protein_daily":      return "fork.knife"
        case "nutrition_streak":   return "flame"
        default:                   return "target"
        }
    }

    var accentColor: String {
        switch type {
        case "body_fat":           return "FF6B35"
        case "lean_mass":          return "2ECC71"
        case "waist_cm":           return "9B59B6"
        case "weekly_volume":      return "3498DB"
        case "training_frequency": return "1ABC9C"
        case "protein_daily":      return "F1C40F"
        case "nutrition_streak":   return "E74C3C"
        default:                   return "FF8C00"
        }
    }

    func formatValue(_ v: Double) -> String {
        switch type {
        case "body_fat":           return String(format: "%.1f%%", v)
        case "lean_mass":          return String(format: "%.1f lbs", v)
        case "waist_cm":           return String(format: "%.1f cm", v)
        case "weekly_volume":      return String(format: "%.0f lbs", v)
        case "training_frequency": return String(format: "%.0f séances", v)
        case "protein_daily":      return String(format: "%.0f g", v)
        case "nutrition_streak":   return String(format: "%.0f jours", v)
        default:                   return String(format: "%.1f %@", v, unit)
        }
    }
}
