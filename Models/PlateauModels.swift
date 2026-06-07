import Foundation
import SwiftUI

struct PlateauResponse: Codable {
    let alerts: [PlateauAlert]
    let computedAt: String

    enum CodingKeys: String, CodingKey {
        case alerts
        case computedAt = "computed_at"
    }
}

struct PlateauAlert: Codable, Identifiable {
    let id: String?
    let exerciseName: String

    var stableId: String { id ?? exerciseName }
    let detectedAt: String
    let plateauScore: Int
    let plateauWeeks: Int
    let rootCause: String
    let severity: String
    let deloadType: String?
    let deloadPlan: DeloadPlan?
    let reboundDaysMin: Int?
    let reboundDaysMax: Int?
    let reboundMessage: String?
    let e1rmSeries: [E1RMPoint]
    let workingWeightLbs: Double
    let workingReps: Int
    let pssContext: PSSAlertContext?
    let nutritionContext: NutritionAlertContext?
    var status: String

    enum CodingKeys: String, CodingKey {
        case id, severity, status
        case exerciseName    = "exercise_name"
        case detectedAt      = "detected_at"
        case plateauScore    = "plateau_score"
        case plateauWeeks    = "plateau_weeks"
        case rootCause       = "root_cause"
        case deloadType      = "deload_type"
        case deloadPlan      = "deload_plan"
        case reboundDaysMin  = "rebound_days_min"
        case reboundDaysMax  = "rebound_days_max"
        case reboundMessage  = "rebound_message"
        case e1rmSeries      = "e1rm_series"
        case workingWeightLbs = "working_weight_lbs"
        case workingReps     = "working_reps"
        case pssContext      = "pss_context"
        case nutritionContext = "nutrition_context"
    }

    var severityColor: Color {
        switch severity {
        case "critical": return .red
        case "warning":  return .orange
        default:         return .yellow
        }
    }

    var severityLabel: String {
        switch severity {
        case "critical": return "CRITIQUE"
        case "warning":  return "PLATEAU"
        default:         return "SURVEILLANCE"
        }
    }

    var rootCauseLabel: String {
        switch rootCause {
        case "overreaching":   return "Surentraînement"
        case "underfueling":   return "Sous-alimentation"
        case "adaptation":     return "Adaptation neuromusculaire"
        case "neural_fatigue": return "Fatigue neurale"
        default:               return "Stagnation détectée"
        }
    }

    var rootCauseIcon: String {
        switch rootCause {
        case "overreaching":   return "bolt.heart.fill"
        case "underfueling":   return "fork.knife"
        case "adaptation":     return "arrow.clockwise"
        case "neural_fatigue": return "waveform.path.ecg"
        default:               return "eye"
        }
    }

    var deloadTypeLabel: String {
        switch deloadType {
        case "rest":            return "Repos complet"
        case "light_week":      return "Semaine light"
        case "rep_range":       return "Changement de reps"
        case "nutrition_first": return "Priorité nutrition"
        default:                return "Deload"
        }
    }

    var deloadTypeIcon: String {
        switch deloadType {
        case "rest":            return "bed.double.fill"
        case "light_week":      return "minus.circle.fill"
        case "rep_range":       return "arrow.triangle.2.circlepath"
        case "nutrition_first": return "leaf.fill"
        default:                return "checkmark.circle.fill"
        }
    }
}

struct E1RMPoint: Codable {
    let date: String
    let e1rmLbs: Double

    enum CodingKeys: String, CodingKey {
        case date
        case e1rmLbs = "e1rm_lbs"
    }
}

struct DeloadPlan: Codable {
    let instruction: String
    let exercises: [DeloadExercise]?
    let returnWeightLbs: Double?
    let returnSets: Int?
    let returnReps: Int?
    let nutritionPrescription: NutritionPrescription?

    enum CodingKeys: String, CodingKey {
        case instruction, exercises
        case returnWeightLbs       = "return_weight_lbs"
        case returnSets            = "return_sets"
        case returnReps            = "return_reps"
        case nutritionPrescription = "nutrition_prescription"
    }
}

struct DeloadExercise: Codable {
    let name: String
    let fromLbs: Double?
    let toLbs: Double?
    let sets: Int?
    let reps: Int?
    let note: String?
    let fromReps: Int?
    let forceOption: RepOption?
    let volumeOption: RepOption?

    enum CodingKeys: String, CodingKey {
        case name, sets, reps, note
        case fromLbs     = "from_lbs"
        case toLbs       = "to_lbs"
        case fromReps    = "from_reps"
        case forceOption  = "force_option"
        case volumeOption = "volume_option"
    }
}

struct RepOption: Codable {
    let weightLbs: Double
    let reps: String

    enum CodingKeys: String, CodingKey {
        case weightLbs = "weight_lbs"
        case reps
    }
}

struct NutritionPrescription: Codable {
    let caloricIncreaseKcal: Int
    let durationDays: Int
    let proteinTargetNote: String

    enum CodingKeys: String, CodingKey {
        case caloricIncreaseKcal  = "caloric_increase_kcal"
        case durationDays         = "duration_days"
        case proteinTargetNote    = "protein_target_note"
    }
}

struct PSSAlertContext: Codable {
    let recentAvg: Double?
    let trend: Double?
    let isHigh: Bool
    let isRising: Bool

    enum CodingKeys: String, CodingKey {
        case trend
        case recentAvg = "recent_avg"
        case isHigh    = "is_high"
        case isRising  = "is_rising"
    }
}

struct NutritionAlertContext: Codable {
    let caloricDeficit: Int?
    let deficitFlag: Bool

    enum CodingKeys: String, CodingKey {
        case caloricDeficit = "caloric_deficit"
        case deficitFlag    = "deficit_flag"
    }
}
